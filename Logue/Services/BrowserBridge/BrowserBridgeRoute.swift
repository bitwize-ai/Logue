import Foundation

/// What the browser bridge answers, and what it refuses.
///
/// Split from the server so the decisions — which paths exist, which origins are allowed, what an
/// unimplemented tool returns — can be tested as plain functions. The server does sockets; this
/// decides meaning.
enum BrowserBridgeRoute {
    /// Endpoints this build serves.
    enum Known: String, CaseIterable {
        case status = "/v1/logue/status"
        case handshake = "/v1/logue/handshake"
        case models = "/v1/models"
        case chatCompletions = "/v1/chat/completions"
        case chat = "/v1/logue/chat"

        /// Whether the endpoint is read-only. `GET` is refused on the rest, so a page that
        /// stumbles onto the port cannot start inference with a link — but reading the status or
        /// the model list starts nothing, and the extension asks for both with `GET`.
        var allowsGet: Bool {
            self == .status || self == .models
        }
    }

    /// Endpoints the extension calls that this build does not serve yet.
    ///
    /// Listed explicitly rather than lumped in with "unknown path" so the answer can be `501 Not
    /// Implemented` with a name the user recognises, instead of a `404` that reads as "you are
    /// talking to the wrong app".
    static let notYetImplemented: Set<String> = [
        "/v1/logue/grammar-check", "/v1/logue/clarity-check", "/v1/logue/tone-detect",
        "/v1/logue/analyze", "/v1/logue/rewrite", "/v1/logue/paraphrase",
        "/v1/logue/humanize", "/v1/logue/fact-check", "/v1/logue/pii-detect",
        "/v1/logue/expert-review", "/v1/logue/ai-grade", "/v1/logue/vocabulary",
        "/v1/logue/reader-reactions", "/v1/logue/ai-content-detect",
        "/v1/logue/citation-find", "/v1/logue/plagiarism-check", "/v1/logue/compose",
    ]

    /// What the server should do with a request, decided before any work is started.
    enum Decision: Equatable {
        case serve(Known)
        case preflight
        case notImplemented(String)
        case notFound
        case methodNotAllowed
        case forbiddenOrigin
    }

    /// The only origin scheme allowed to call in.
    ///
    /// Not authentication — the user was clear it should just work, and a browser sets this
    /// header itself so a page cannot forge it. What it does buy is that an ordinary website
    /// cannot quietly use the machine's model: the browser refuses to hand it the response.
    /// A request with no `Origin` at all is allowed, because that is `curl` on the user's own
    /// machine, which they are entitled to do.
    private static let allowedOriginScheme = "chrome-extension://"

    static func isAllowed(origin: String?) -> Bool {
        guard let origin, !origin.isEmpty, origin != "null" else { return true }
        return origin.hasPrefix(allowedOriginScheme)
    }

    /// Decides how to answer, without doing any of the work.
    static func decide(method: String, path: String, origin: String?) -> Decision {
        guard isAllowed(origin: origin) else { return .forbiddenOrigin }

        let route = HTTPMessage.route(from: path)

        // A browser sends this before a cross-origin POST, and answering it is what lets the real
        // request through.
        if method == "OPTIONS" {
            return .preflight
        }

        if let known = Known(rawValue: route) {
            switch method {
            case "GET" where known.allowsGet, "POST":
                return .serve(known)
            default:
                return .methodNotAllowed
            }
        }

        if notYetImplemented.contains(route) {
            return .notImplemented(route)
        }
        return .notFound
    }

    /// The message shown when a tool this build does not serve is opened.
    ///
    /// Names the tool and says the app is otherwise fine, because the alternative — a bare
    /// failure — reads as "Logue is broken" rather than "that button does nothing yet".
    static func notImplementedMessage(for route: String) -> String {
        let tool = route.split(separator: "/").last.map(String.init) ?? "That tool"
        let readable = tool.replacingOccurrences(of: "-", with: " ")
        return "Logue is connected, but \(readable) is not available from the browser yet."
    }
}
