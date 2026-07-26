import Foundation
import OSLog
import SwiftUI
import WebKit

// MARK: - Mermaid Block

/// A Mermaid diagram block: rendered preview when unfocused, editable source when focused.
///
/// The source is the durable representation — it round-trips as a ```` ```mermaid ````
/// fence — so the preview is always derived and never the source of truth.
struct MermaidBlockView: View {
    let source: String
    let isFocused: Bool
    let fontSize: CGFloat
    let onSourceChange: (String) -> Void
    let onFocusRequested: () -> Void

    @State private var svg: String?
    @State private var renderError: String?
    @State private var renderTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.bitwize.logue", category: "MermaidBlock")

    var body: some View {
        Group {
            if isFocused {
                BlockSourceEditor(
                    text: source,
                    fontSize: fontSize,
                    placeholder: "flowchart LR\n  A --> B",
                    onTextChange: onSourceChange
                )
            } else {
                preview
            }
        }
        .task(id: source) { await render() }
        .onDisappear { renderTask?.cancel() }
    }

    @ViewBuilder
    private var preview: some View {
        if let svg {
            SVGWebView(svg: svg)
                .frame(minHeight: 80)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFocusRequested)
        } else if let renderError {
            BlockSourceFallback(
                source: source,
                fontSize: fontSize,
                message: renderError,
                onTap: onFocusRequested
            )
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFocusRequested)
        }
    }

    private func render() async {
        let code = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            svg = nil
            renderError = "Empty diagram"
            return
        }

        do {
            let rendered = try await MermaidRenderer.shared.renderSVG(code: code)
            guard !Task.isCancelled else { return }
            svg = rendered
            renderError = nil
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.error("Mermaid render failed: \(error.localizedDescription, privacy: .public)")
            svg = nil
            renderError = "Diagram could not be rendered"
        }
    }
}

// MARK: - Math Block

/// A display-math block. The LaTeX source is durable between `$$` fences.
struct MathBlockView: View {
    let latex: String
    let isFocused: Bool
    let fontSize: CGFloat
    let onLatexChange: (String) -> Void
    let onFocusRequested: () -> Void

    var body: some View {
        if isFocused {
            BlockSourceEditor(
                text: latex,
                fontSize: fontSize,
                placeholder: "E = mc^2",
                onTextChange: onLatexChange
            )
        } else if latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Empty equation")
                .font(.system(size: fontSize))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFocusRequested)
        } else {
            InlineLaTeXView(messageContent: "$$\n\(latex)\n$$")
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFocusRequested)
        }
    }
}

// MARK: - Shared Source Editor

/// Monospaced source editor shared by the diagram and math blocks.
///
/// These blocks are source surfaces rather than prose, so they use a plain
/// `TextEditor` instead of the rich `BlockTextView` — no markdown styling,
/// suggestion overlay, or list continuation applies to diagram or LaTeX source.
private struct BlockSourceEditor: View {
    let text: String
    let fontSize: CGFloat
    let placeholder: String
    let onTextChange: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize * 0.882, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft)
                .font(.system(size: fontSize * 0.882, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 80)
        }
        .background(AppThemeConstants.codeBlockBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppThemeConstants.codeBlockBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { draft = text }
        .onChange(of: draft) { _, newValue in onTextChange(newValue) }
        .onChange(of: text) { _, newValue in
            // Adopt external edits (undo, AI rewrite) without clobbering typing.
            if newValue != draft {
                draft = newValue
            }
        }
    }
}

// MARK: - Source Fallback

/// Shown when a diagram cannot be rendered — the source stays visible and editable
/// rather than the block appearing empty.
private struct BlockSourceFallback: View {
    let source: String
    let fontSize: CGFloat
    let message: String
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: fontSize * 0.8))
                .foregroundStyle(.secondary)
            Text(source)
                .font(.system(size: fontSize * 0.882, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppThemeConstants.codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - SVG Rendering

/// Renders an SVG string in a local `WKWebView`.
///
/// Loaded with a `nil` base URL and JavaScript disabled so the diagram markup
/// cannot reach the network or execute script.
private struct SVGWebView: NSViewRepresentable {
    let svg: String

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        webView.loadHTMLString(Self.wrap(svg: svg), baseURL: nil)
    }

    private static func wrap(svg: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        </style>
        </head><body>\(svg)</body></html>
        """
    }
}
