import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Phase C: right-side artifact pane for code/HTML/Mermaid responses.
/// Renders a versioned snapshot strip on top, the source on the left,
/// and (for HTML/Mermaid) a live preview on the right.
///
/// The state is owned by `CanvasController` so multiple chat surfaces can
/// drive it. AgentChatView opens the pane when an assistant turn produces
/// a fenced code block longer than 30 lines OR matches a preview-eligible
/// language (html / mermaid).
struct CanvasPaneView: View {
    @State private var controller = CanvasController.shared
    @State private var selectedTab: CanvasTab = .preview

    private enum CanvasTab { case preview, source }

    var body: some View {
        if !controller.snapshots.isEmpty {
            VStack(spacing: 0) {
                header
                Divider()
                versionStrip
                Divider()
                content
            }
            .frame(minWidth: 360)
            .background(Color(NSColor.textBackgroundColor))
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Canvas")
                .font(.callout.weight(.semibold))
            if let active = controller.active {
                Text(active.language.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // Phase H: when the active snapshot is a slide deck, surface
            // a one-click Export PDF button next to the menu — most
            // users will reach for this immediately.
            if controller.active?.isSlideDeck == true {
                Button {
                    exportSlideDeckPDF()
                } label: {
                    Label("Export PDF", systemImage: "arrow.down.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Menu {
                Button("Copy", action: copyActive)
                Button("Save as file…", action: saveActive)
                if controller.active?.isSlideDeck == true {
                    Button("Export PDF…", action: exportSlideDeckPDF)
                }
                Divider()
                Button("Close Canvas", role: .destructive) {
                    withAnimation(Motion.spring) { controller.dismiss() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var versionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(controller.snapshots) { snapshot in
                    versionChip(snapshot)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func versionChip(_ snapshot: CanvasSnapshot) -> some View {
        let isActive = controller.activeID == snapshot.id
        return Button {
            controller.activeID = snapshot.id
        } label: {
            Text(snapshot.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(snapshot.createdAt.formatted(date: .omitted, time: .shortened))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = controller.active {
            if snapshot.supportsPreview {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    Group {
                        switch selectedTab {
                        case .preview: previewPane(for: snapshot)
                        case .source: sourcePane(snapshot.content)
                        }
                    }
                }
            } else {
                sourcePane(snapshot.content)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(title: "Preview", systemImage: "eye", tab: .preview)
            tabButton(title: "Source", systemImage: "chevron.left.forwardslash.chevron.right", tab: .source)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func tabButton(title: String, systemImage: String, tab: CanvasTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(Motion.spring) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func sourcePane(_ source: String) -> some View {
        ScrollView {
            Text(source)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func previewPane(for snapshot: CanvasSnapshot) -> some View {
        switch snapshot.language.lowercased() {
        case "html", "svg", "slidedeck":
            // Phase H: slide decks are full HTML documents, so they
            // route through the same WebKit preview path as html/svg.
            WebPreviewView(html: snapshot.content)
                .frame(minWidth: 200)
        case "mermaid":
            MermaidWebPreview(source: snapshot.content)
                .frame(minWidth: 200)
        default:
            Color.clear
        }
    }

    // MARK: - Actions

    private func copyActive() {
        guard let active = controller.active else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(active.content, forType: .string)
        HapticFeedback.copy()
        ToastCenter.shared.show(UICopy.Toast.copied)
    }

    private func saveActive() {
        guard let active = controller.active else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.exportTypes(for: active.language)
        panel.nameFieldStringValue = "canvas-\(active.label)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try active.content.write(to: url, atomically: true, encoding: .utf8)
                ToastCenter.shared.show(UICopy.Toast.saved)
            } catch {
                ToastCenter.shared.show("Couldn't save", kind: .warning)
            }
        }
    }

    private static func exportTypes(for language: String) -> [UTType] {
        switch language.lowercased() {
        case "html", "svg", "slidedeck": [.html, .plainText]
        case "swift": [UTType("public.swift-source") ?? .plainText, .plainText]
        case "mermaid": [UTType("net.daringfireball.markdown") ?? .plainText, .plainText]
        case "json": [.json, .plainText]
        default: [.plainText]
        }
    }

    /// Phase H: print-to-PDF the active slide deck snapshot via the
    /// shared `DeckPDFExporter`. Sandbox-safe — uses an off-screen
    /// `WKWebView` + `NSPrintInfo.jobDisposition = .save`.
    private func exportSlideDeckPDF() {
        guard let active = controller.active, active.isSlideDeck else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "deck.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DeckPDFExporter.export(html: active.content, to: url) { result in
            switch result {
            case .success:
                ToastCenter.shared.show(UICopy.Toast.saved)
            case let .failure(error):
                ToastCenter.shared.show("Export failed: \(error.localizedDescription)", kind: .warning)
            }
        }
    }
}

// MARK: - Web previews (WKWebView wrappers)

private struct WebPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}

private struct MermaidWebPreview: NSViewRepresentable {
    let source: String

    /// Bundled mermaid.min.js, loaded once and inlined into the scaffold so the
    /// preview renders fully on-device — no CDN import, no network egress, and
    /// no remote code execution (matches `MermaidRenderer`'s local-load pattern).
    private static let mermaidJS: String = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") else {
            os_log(.error, "mermaid.min.js not found in bundle")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            os_log(.error, "Failed to read bundled mermaid.min.js: %{public}@", error.localizedDescription)
            return ""
        }
    }()

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let safeSource = source.replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>body{margin:0;font-family:-apple-system}</style></head>
        <body>
          <pre class="mermaid">\(safeSource)</pre>
          <script>\(Self.mermaidJS)</script>
          <script>
            if (window.mermaid) {
              window.mermaid.initialize({ startOnLoad: true, securityLevel: "strict" });
            }
          </script>
        </body></html>
        """
        // baseURL nil → fully local context, no network access.
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
