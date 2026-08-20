import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Action row shown beneath each settled assistant message. Provides Copy,
/// Export-as-Markdown, Read-Aloud (Phase 9), and Visualize-Table (Phase 8).
/// Owns its own sheet state for the chart visualizer.
struct AssistantActionRow: View {
    let content: String
    @State private var chartTable: ChartTable?
    /// Ticks the save button for a moment, so the action confirms itself where it happened
    /// rather than only in a toast the user may be looking away from.
    @State private var savedNote = false

    @State private var readAloud = AgentReadAloudService.shared

    private var detectedTable: ChartTable? {
        ChartTypeInferrer.parseFirstTable(from: content)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                MessageActions.copyToClipboard(content)
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
                MessageActions.saveAsNote(content)
                savedNote = true
                Task {
                    try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
                    savedNote = false
                }
            } label: {
                Image(systemName: savedNote ? "checkmark" : "square.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save response as a note")

            Button {
                MessageActions.exportMarkdown(content)
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
