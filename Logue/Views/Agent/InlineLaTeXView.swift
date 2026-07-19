import AppKit
import SwiftUI
import WebKit

/// Phase G: detects LaTeX expressions in assistant messages and renders
/// them inline below the markdown text. Mirrors the pattern used by
/// `InlineDiagramView` (separate block under the message) but uses
/// KaTeX rather than Mermaid.
///
/// Recognised forms:
///   - `$$ … $$` block math
///   - `\[ … \]` block math
///   - `$ … $` inline math (rendered as a single-row block — full inline
///     wrapping inside the markdown text would need a custom AST pass)
struct InlineLaTeXView: View {
    let messageContent: String

    private static let blockPatterns: [NSRegularExpression] = {
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"\$\$([^\$]+)\$\$"#, [.dotMatchesLineSeparators]),
            (#"\\\[([\s\S]+?)\\\]"#, []),
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0.0, options: $0.1) }
    }()

    private static let inlinePattern: NSRegularExpression? = try? NSRegularExpression(
        // Single $...$ but not $$...$$ (the block pattern handles those).
        pattern: #"(?<!\$)\$([^\$\n]{1,400})\$(?!\$)"#,
        options: []
    )

    var body: some View {
        let blocks = extract(from: messageContent)
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(blocks, id: \.id) { entry in
                    KaTeXWebView(latex: entry.latex, isBlock: entry.isBlock)
                        .frame(maxWidth: .infinity)
                        .frame(height: entry.isBlock ? 64 : 32)
                        .background(Color.secondary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
        }
    }

    // MARK: - Extraction

    private struct MathBlock: Identifiable {
        let id = UUID()
        let latex: String
        let isBlock: Bool
    }

    private func extract(from text: String) -> [MathBlock] {
        var found: [MathBlock] = []
        var seen = Set<String>()
        let range = NSRange(text.startIndex..., in: text)

        for regex in Self.blockPatterns {
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let hit = match,
                      hit.numberOfRanges >= 2,
                      let inner = Range(hit.range(at: 1), in: text)
                else { return }
                let latex = String(text[inner]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty, !seen.contains(latex) else { return }
                seen.insert(latex)
                found.append(MathBlock(latex: latex, isBlock: true))
            }
        }

        // Skip inline matches if any block already covers them — avoids
        // double-rendering when $$x$$ contains a `$x$` substring.
        if found.isEmpty, let inlineRegex = Self.inlinePattern {
            inlineRegex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let hit = match,
                      hit.numberOfRanges >= 2,
                      let inner = Range(hit.range(at: 1), in: text)
                else { return }
                let latex = String(text[inner]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty, !seen.contains(latex) else { return }
                seen.insert(latex)
                found.append(MathBlock(latex: latex, isBlock: false))
            }
        }
        // Cap at 8 to avoid blowing up message height on a corner case.
        return Array(found.prefix(8))
    }
}

// MARK: - WebView shim

/// Loads KaTeX from the bundled JS/CSS and renders the supplied LaTeX
/// string in a transparent WKWebView. The webview height is fixed by
/// the parent — KaTeX scales the formula to fit.
private struct KaTeXWebView: NSViewRepresentable {
    let latex: String
    let isBlock: Bool

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: bundleResourcesBaseURL())
    }

    /// Build the HTML scaffold that loads KaTeX and renders one expression.
    private var html: String {
        let escapedLatex = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let displayMode = isBlock ? "true" : "false"
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8"/>
        <link rel="stylesheet" href="katex.min.css"/>
        <script src="katex.min.js"></script>
        <style>
          body { margin:0; padding:6px 10px; background: transparent;
                 font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                 color: #e0e0e0;
                 display: flex; align-items: center; }
          .out { width: 100%; overflow-x: auto; }
          .err { color: #ff8888; font-family: ui-monospace; font-size: 12px; }
        </style>
        </head><body>
          <div class="out" id="out"></div>
          <script>
            try {
              katex.render("\(escapedLatex)", document.getElementById("out"), {
                throwOnError: false,
                displayMode: \(displayMode),
                output: "html"
              });
            } catch (e) {
              document.getElementById("out").innerHTML =
                '<span class="err">' + (e.message || 'render error') + '</span>';
            }
          </script>
        </body></html>
        """
    }

    /// KaTeX needs to load `katex.min.css` (and the WOFF2 fonts it
    /// references) from a relative URL. The Resources folder of the
    /// app bundle contains them all, so we use it as the baseURL.
    private func bundleResourcesBaseURL() -> URL? {
        Bundle.main.resourceURL
    }
}
