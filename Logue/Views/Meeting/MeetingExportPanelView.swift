import os.log
import SwiftUI
import UniformTypeIdentifiers

/// Right panel for exporting meeting data in various formats.
struct MeetingExportPanelView: View {
    let meeting: MeetingNote
    @State private var exportStatus: String?

    var body: some View {
        List {
            Section("Export") {
                ExportOptionButton(
                    title: "Full Transcript",
                    subtitle: "Plain text with timestamps and speaker labels",
                    icon: "doc.text",
                    action: { exportTranscript() }
                )

                ExportOptionButton(
                    title: "Smart Minutes",
                    subtitle: "Structured summary with decisions, action items, and follow-ups",
                    icon: "doc.plaintext",
                    action: { exportSmartMinutes() }
                )

                ExportOptionButton(
                    title: "Action Items",
                    subtitle: "Checklist of action items with assignees",
                    icon: "checklist",
                    action: { exportActionItems() }
                )

                ExportOptionButton(
                    title: "Markdown",
                    subtitle: "Full meeting notes in Markdown format",
                    icon: "text.document",
                    action: { exportMarkdown() }
                )

                if !meeting.bookmarks.isEmpty {
                    ExportOptionButton(
                        title: "Bookmarked Moments",
                        subtitle: "\(meeting.bookmarks.count) bookmarks with transcript context",
                        icon: "bookmark.fill",
                        action: { exportBookmarks() }
                    )
                }
            }

            Section("Quick Copy") {
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard(meeting.fullTranscript)
                    } label: {
                        Label("Transcript", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        let content = meeting.smartMinutes != nil
                            ? meeting.smartMinutesMarkdown()
                            : (meeting.summary ?? "No summary available")
                        copyToClipboard(content)
                    } label: {
                        Label("Summary", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let status = exportStatus {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppThemeConstants.success)
                        .transition(.opacity)
                }
            }

            Section {
                PrivacyBadge("Exported files stay on your device.")
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Instance Export Methods (delegate to static)

    private func exportTranscript() {
        Self.exportTranscript(meeting: meeting)
    }

    private func exportSmartMinutes() {
        Self.exportSmartMinutes(meeting: meeting)
    }

    private func exportActionItems() {
        Self.exportActionItems(meeting: meeting)
    }

    private func exportBookmarks() {
        Self.exportBookmarks(meeting: meeting)
    }

    private func exportMarkdown() {
        Self.exportMarkdown(meeting: meeting)
    }

    private func copyToClipboard(_ text: String) {
        Self.copyToClipboard(text)
        exportStatus = "Copied to clipboard"
        Task {
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            await MainActor.run { exportStatus = nil }
        }
    }

    // MARK: - Static Export Methods

    static func exportTranscript(meeting: MeetingNote) {
        let content = meeting.fullTranscript
        saveFile(content: content, defaultName: "\(meeting.title) - Transcript.txt", contentType: .plainText)
    }

    static func exportSmartMinutes(meeting: MeetingNote) {
        let content = meeting.smartMinutesMarkdown()
        saveFile(content: content, defaultName: "\(meeting.title) - Minutes.md", contentType: .plainText)
    }

    static func exportActionItems(meeting: MeetingNote) {
        var content = "# Action Items — \(meeting.title)\n\n"
        for item in meeting.actionItems {
            let check = item.isCompleted ? "[x]" : "[ ]"
            var line = "- \(check) \(item.title)"
            if let assignee = item.assignee {
                line += " (@\(assignee))"
            }
            if let due = item.dueDescription {
                line += " — due: \(due)"
            }
            content += line + "\n"
        }
        saveFile(content: content, defaultName: "\(meeting.title) - Action Items.md", contentType: .plainText)
    }

    static func exportBookmarks(meeting: MeetingNote) {
        var content = "# Bookmarked Moments — \(meeting.title)\n\n"
        content += "**Date:** \(meeting.createdAt.formatted())\n"
        content += "**Bookmarks:** \(meeting.bookmarks.count)\n\n"

        for bookmark in meeting.bookmarks.sorted(by: { $0.timestamp < $1.timestamp }) {
            let label = bookmark.label.isEmpty ? "Bookmark" : bookmark.label
            content += "## [\(bookmark.formattedTimestamp)] \(label)\n\n"

            let nearby = meeting.segments.filter { segment in
                segment.startTime >= bookmark.timestamp - 5 && segment.startTime <= bookmark.timestamp + 10
            }
            if nearby.isEmpty {
                content += "_No transcript at this timestamp._\n\n"
            } else {
                for segment in nearby {
                    let speaker = segment.speakerLabel ?? "Speaker"
                    content += "> [\(segment.formattedStartTime)] **\(speaker):** \(segment.text)\n"
                }
                content += "\n"
            }
        }

        saveFile(content: content, defaultName: "\(meeting.title) - Bookmarks.md", contentType: .plainText)
    }

    static func exportMarkdown(meeting: MeetingNote) {
        var content = "# \(meeting.title)\n\n"
        content += "**Date:** \(meeting.createdAt.formatted())\n"
        content += "**Duration:** \(meeting.formattedDuration)\n"
        content += "**Mode:** \(meeting.recordingMode.label)\n\n"

        if let summary = meeting.summary {
            content += "## Summary\n\n\(summary)\n\n"
        }

        if let minutes = meeting.smartMinutes, !minutes.actionItems.isEmpty {
            content += "## Action Items\n\n"
            for item in minutes.actionItems {
                content += "- [ ] \(item)\n"
            }
            content += "\n"
        }

        content += "## Transcript\n\n"
        content += meeting.fullTranscript

        saveFile(content: content, defaultName: "\(meeting.title).md", contentType: .plainText)
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func saveFile(content: String, defaultName: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [contentType]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "Export")
                    .error("Export failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Export Option Button

private struct ExportOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.down.to.line")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export \(title)")
        .accessibilityHint(subtitle)
    }
}
