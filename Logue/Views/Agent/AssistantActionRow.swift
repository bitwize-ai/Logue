import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Action row shown beneath each settled assistant message. Provides Copy,
/// Export-as-Markdown, Read-Aloud (Phase 9), and Visualize-Table (Phase 8).
/// Owns its own sheet state for the chart visualizer.
struct AssistantActionRow: View {
    let content: String
    @State private var chartTable: ChartTable?

    @State private var readAloud = AgentReadAloudService.shared

    private var detectedTable: ChartTable? {
        ChartTypeInferrer.parseFirstTable(from: content)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                copyToClipboard(content)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy response")

            Button {
                exportMarkdown(content)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Export response as Markdown")

            Button {
                if readAloud.isSpeaking(content: content) {
                    readAloud.stop()
                } else {
                    readAloud.speak(content)
                }
            } label: {
                Image(systemName: readAloud.isSpeaking(content: content) ? "stop.circle" : "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(readAloud.isSpeaking(content: content) ? "Stop reading" : "Read aloud")

            if detectedTable != nil {
                Button {
                    chartTable = detectedTable
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                        Text("Visualize")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Render the table as a chart")
            }
        }
        .padding(.leading, 10)
        .sheet(item: $chartTable) { table in
            AutoChartView(table: table)
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HapticFeedback.copy()
        Task { @MainActor in
            ToastCenter.shared.show(UICopy.Toast.copied)
        }
    }

    private func exportMarkdown(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown") ?? .plainText]
        panel.nameFieldStringValue = "logue-response.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Failed to export markdown: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ChartTable Identifiable

/// `ChartTable` is the source for a sheet — `.sheet(item:)` requires `Identifiable`.
/// The hash conformance is good enough since each parse run produces the same
/// table for the same input message.
extension ChartTable: Identifiable {
    var id: Int {
        var hasher = Hasher()
        hasher.combine(headers)
        for row in rows {
            hasher.combine(row)
        }
        return hasher.finalize()
    }
}
