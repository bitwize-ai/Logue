import AppKit
import SwiftUI
import WebKit

/// Phase C polish: assistants emit `![Alt](file:///…/AgentDiagrams/foo.svg)`
/// when they invoke `render_diagram`. The default markdown renderer doesn't
/// know how to load file:// URLs, so this small SwiftUI shim scans message
/// content for diagram references and embeds them inline below the markdown.
///
/// Only file URLs that point inside Logue's `AgentDiagrams` cache are loaded
/// — opening arbitrary file:// URLs from LLM output would be a sandbox escape.
struct InlineDiagramView: View {
    let messageContent: String

    /// Matches `![Alt](file:///…AgentDiagrams/foo.svg)` markdown image syntax.
    private static let markdownPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\((file://[^\)]+\.svg)\)"#,
        options: []
    )

    /// Matches the bare path the `render_diagram` tool emits in its result —
    /// this is our fallback when the model omits the markdown image syntax.
    private static let bareDiagramPathPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(/[^\s\)]+/AgentDiagrams/[^\s\)]+\.svg)"#,
        options: []
    )

    var body: some View {
        let matches = extractDiagramURLs(from: messageContent)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(matches, id: \.url) { entry in
                    diagramCell(entry)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Cell

    private func diagramCell(_ entry: DiagramRef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.alt.isEmpty ? "Diagram" : entry.alt)
                .font(.caption2)
                .foregroundStyle(.secondary)
            SVGFileView(url: entry.url)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(entry.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Parsing

    private func extractDiagramURLs(from text: String) -> [DiagramRef] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [DiagramRef] = []
        var seenPaths = Set<String>()

        // 1) Markdown-image syntax (preferred — carries an alt text).
        if let regex = Self.markdownPattern {
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let hit = match,
                      hit.numberOfRanges >= 3,
                      let altRange = Range(hit.range(at: 1), in: text),
                      let urlRange = Range(hit.range(at: 2), in: text),
                      let url = URL(string: String(text[urlRange])),
                      url.path.contains("AgentDiagrams"),
                      !seenPaths.contains(url.path)
                else { return }
                seenPaths.insert(url.path)
                found.append(DiagramRef(alt: String(text[altRange]), url: url))
            }
        }

        // 2) Bare path fallback — happens when the model writes plain prose
        // ("Saved diagram to /Users/.../AgentDiagrams/foo.svg") without the
        // markdown image syntax. Triggered only if no markdown match landed.
        if found.isEmpty, let regex = Self.bareDiagramPathPattern {
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let hit = match,
                      let pathRange = Range(hit.range(at: 1), in: text)
                else { return }
                let path = String(text[pathRange])
                guard !seenPaths.contains(path) else { return }
                seenPaths.insert(path)
                let url = URL(fileURLWithPath: path)
                let alt = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-", with: " ")
                found.append(DiagramRef(alt: alt, url: url))
            }
        }
        return found
    }

    private struct DiagramRef {
        let alt: String
        let url: URL
    }
}

// MARK: - WKWebView shim

/// Loads an SVG file URL into a transparent WKWebView. Centered, scales to fit.
private struct SVGFileView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
            nsView.loadHTMLString(
                "<html><body style='color:gray;font-family:-apple-system'>Couldn't load diagram</body></html>",
                baseURL: nil
            )
            return
        }
        let html = """
        <!DOCTYPE html>
        <html><head><style>
          body { margin: 0; display: flex; align-items: center; justify-content: center;
                 min-height: 100vh; background: transparent; }
          svg { max-width: 95%; max-height: 95%; }
        </style></head>
        <body>\(svg)</body></html>
        """
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
