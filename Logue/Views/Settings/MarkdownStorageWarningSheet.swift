import AppKit
import SwiftUI

/// Shown before documents stop being encrypted.
///
/// Written to be read, not clicked past. Every line is something the user could
/// reasonably be upset to discover afterwards — especially the iCloud one, which is a
/// consequence of the folder's location rather than of anything they asked for.
struct MarkdownStorageWarningSheet: View {
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            points
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.open.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Store documents as plain markdown?")
                    .font(.headline)
                Text("This changes where your documents live and removes their encryption.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 10) {
            point(
                "folder",
                "Documents move to \(DocumentStorage.markdownRootURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))",
                "One .md file per document, organised into folders matching your spaces."
            )
            point(
                "lock.open",
                "They will no longer be encrypted",
                "Any app, script, or AI agent that can read your home folder can read them."
            )
            point(
                "icloud",
                "Your Documents folder may sync to iCloud",
                "If it does, unencrypted copies of your notes go to iCloud too. Check System "
                    + "Settings → Apple Account → iCloud Drive if you are unsure."
            )
            point(
                "waveform",
                "Meetings stay encrypted",
                "Transcripts, audio, summaries and action items are unaffected."
            )
            point(
                "trash",
                "Trash stays inside Logue",
                "Deleted documents are not written to the folder. They stay in encrypted "
                    + "storage and are back in Trash if you turn this off."
            )
            point(
                "arrow.uturn.backward",
                "You can turn this off later",
                "Turning it off moves documents back into encrypted storage and leaves the "
                    + "folder in place."
            )
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasAcknowledged) {
                Text("I understand my documents will not be encrypted")
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Turn On") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAcknowledged)
            }
        }
    }
}
