import AppKit
import Foundation
import os.log
import WebKit

/// Renders Mermaid diagrams to SVG using a hidden `WKWebView` + the bundled
/// `mermaid.min.js`. Sandbox-safe (no subprocess), Apple-frameworks-only.
///
/// Pattern: each render builds an HTML scaffold containing `mermaid.min.js`
/// inline plus a one-shot `mermaid.render()` call. We `await` the JS promise
/// via `callAsyncJavaScript`, returning the SVG string. If Mermaid throws
/// (invalid syntax), the error message is returned in `MermaidError.parseFailed`
/// so the caller can feed it back to the LLM with the cheatsheet.
@MainActor
final class MermaidRenderer {
    static let shared = MermaidRenderer()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MermaidRenderer")

    /// Cached library + cheatsheet. Loaded once per process.
    private lazy var mermaidJS: String = Self.loadMermaidJS(logger: logger)
    private lazy var cheatsheet: String = Self.loadCheatsheet(logger: logger)

    /// Cached web view. Reused across renders; navigated via per-call HTML strings.
    private var webView: WKWebView?
    /// Per-call delegate used to drive the navigation completion handler.
    private var currentNavigation: NavigationGate?

    enum MermaidError: Error, LocalizedError {
        case libraryUnavailable
        case parseFailed(String)
        case renderFailed(String)

        var errorDescription: String? {
            switch self {
            case .libraryUnavailable: "Mermaid library could not be loaded."
            case let .parseFailed(detail): "Mermaid parse error: \(detail)"
            case let .renderFailed(detail): "Mermaid render error: \(detail)"
            }
        }
    }

    /// In-flight render task. Concurrent `renderSVG` callers chain onto this so
    /// only one render runs at a time against the shared WKWebView. Without
    /// serialization the second caller would overwrite `currentNavigation` and
    /// the first caller's `gate.wait()` would never resolve (or worse, resolve
    /// against the wrong navigation, returning a stale or in-progress SVG).
    private var inFlight: Task<String, Error>?
    /// Token incremented on every render. Lets us clear `inFlight` only when
    /// no newer call has replaced it (Task is a struct — can't use `===`).
    private var inFlightToken: Int = 0

    private init() {}

    // MARK: - Public

    /// Returns the SVG string for `code`. Throws `MermaidError.parseFailed` on
    /// invalid Mermaid syntax (the message is the underlying parser error).
    /// Calls are serialized — concurrent callers wait for each other.
    func renderSVG(code: String) async throws -> String {
        guard !mermaidJS.isEmpty else { throw MermaidError.libraryUnavailable }

        // Chain onto any in-flight render. We deliberately ignore the prior
        // result/error — each caller gets their own outcome from the task we
        // create below.
        let prior = inFlight
        let task = Task { [weak self] () throws -> String in
            // Wait for the previous render (if any) before touching the shared
            // WKWebView. Prior errors don't propagate — we just need the
            // serialization barrier.
            _ = try? await prior?.value
            guard let self else { throw MermaidError.renderFailed("Renderer deallocated") }
            return try await self.performRender(code: code)
        }
        inFlightToken += 1
        let myToken = inFlightToken
        inFlight = task
        defer {
            // Only clear if no newer call has replaced our task.
            if inFlightToken == myToken {
                inFlight = nil
            }
        }
        return try await task.value
    }

    /// Actual single-render path. Only ever called from `renderSVG` with the
    /// serialization gate held, so the WKWebView and `currentNavigation` slot
    /// are never racing here.
    private func performRender(code: String) async throws -> String {
        let html = Self.buildHTML(mermaidJS: mermaidJS, mermaidCode: code)
        let view = ensureWebView()

        // Drive WKNavigation completion via a per-call gate.
        let gate = NavigationGate()
        currentNavigation = gate
        view.navigationDelegate = gate

        view.loadHTMLString(html, baseURL: nil)
        do {
            try await gate.wait()
        } catch {
            throw MermaidError.renderFailed(error.localizedDescription)
        }

        // The JS scaffold parks the result on `window.__logueSvg` / `window.__logueErr`
        // so we can read it back with a single evaluateJavaScript without race risk.
        do {
            if let err = try await view.evaluateJavaScript("window.__logueErr || ''") as? String,
               !err.isEmpty
            {
                throw MermaidError.parseFailed(err)
            }
            if let svg = try await view.evaluateJavaScript("window.__logueSvg || ''") as? String,
               !svg.isEmpty
            {
                return svg
            }
            throw MermaidError.renderFailed("No SVG produced")
        } catch let err as MermaidError {
            throw err
        } catch {
            throw MermaidError.renderFailed(error.localizedDescription)
        }
    }

    /// Cheatsheet text bundled with the app. Used by `DiagramTools` to enrich
    /// retry-on-error feedback when the model emits invalid Mermaid syntax.
    var cheatsheetText: String {
        cheatsheet
    }

    // MARK: - WebView

    private func ensureWebView() -> WKWebView {
        if let view = webView {
            return view
        }
        let config = WKWebViewConfiguration()
        // Disallow opening new windows / external nav from inside the rendered page.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView = view
        return view
    }

    // MARK: - Loaders

    private static func loadMermaidJS(logger: Logger) -> String {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") else {
            logger.error("mermaid.min.js not found in bundle")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("Failed to read mermaid.min.js: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    private static func loadCheatsheet(logger: Logger) -> String {
        guard let url = Bundle.main.url(forResource: "mermaidCheatsheet", withExtension: "md") else {
            logger.warning("mermaidCheatsheet.md not found in bundle")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.warning("Failed to read mermaidCheatsheet.md: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    // MARK: - HTML scaffold

    /// Builds a self-contained HTML page that:
    /// 1. Inlines `mermaid.min.js` (bundled).
    /// 2. Calls `mermaid.render()` on the supplied diagram code.
    /// 3. Stores the SVG on `window.__logueSvg` (or the error on `window.__logueErr`).
    ///
    /// The diagram code is JSON-escaped so quotes / backslashes / newlines don't
    /// break out of the JS string literal.
    private static func buildHTML(mermaidJS: String, mermaidCode: String) -> String {
        let escapedCode = jsonEscape(mermaidCode)
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>body{margin:0}</style></head>
        <body>
        <script>\(mermaidJS)</script>
        <script>
        (async () => {
            window.__logueSvg = "";
            window.__logueErr = "";
            try {
                if (!window.mermaid) throw new Error("mermaid library failed to load");
                window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "default" });
                const id = "logue-diagram-" + Date.now();
                const result = await window.mermaid.render(id, \(escapedCode));
                window.__logueSvg = result.svg || "";
            } catch (err) {
                window.__logueErr = (err && err.message) ? err.message : String(err);
            }
        })();
        </script>
        </body></html>
        """
    }

    /// JSON-escapes a string so it can be dropped between double quotes in JS.
    /// Avoids pulling JSONSerialization for a single string literal.
    private static func jsonEscape(_ raw: String) -> String {
        var out = "\""
        for ch in raw {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            // U+2028 / U+2029 are valid in JSON strings but illegal as raw chars
            // inside JS string literals (some engines treat them as line
            // terminators). Escape them so a copy-pasted Mermaid snippet with
            // weird Unicode whitespace doesn't break the scaffold.
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if let scalar = ch.unicodeScalars.first, scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(ch)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - NavigationGate

/// Bridges `WKNavigationDelegate` callbacks into an async/await primitive so
/// `MermaidRenderer.renderSVG` can `await` the load completion.
@MainActor
private final class NavigationGate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var isResolved = false

    func wait() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        resolve(.success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        resolve(.failure(error))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard !isResolved else { return }
        isResolved = true
        switch result {
        case .success:
            continuation?.resume()
        case let .failure(err):
            continuation?.resume(throwing: err)
        }
        continuation = nil
    }
}
