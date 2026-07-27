import AppKit
import SwiftUI

// MARK: - Banner

/// Shown above a document whose mirror file has diverged.
///
/// Deliberately prominent and non-dismissible: the document on screen is not the only
/// version of itself, and silently continuing to edit would make one side's work
/// harder to recover the longer it goes unnoticed.
struct MirrorConflictBanner: View {
    let conflict: MirrorConflict
    let onResolve: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("This document was also edited outside Logue")
                    .font(.subheadline.weight(.semibold))
                Text("Both versions have changes. Nothing has been overwritten — choose which to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Review", action: onResolve)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conflict: this document was also edited outside Logue")
    }
}

// MARK: - Resolution Sheet

/// Side-by-side comparison with an explicit choice.
///
/// There is no "merge automatically" option: the two versions are both real work and
/// guessing a merge is how edits get silently lost. The user picks a side, and the
/// other version stays available on disk or in the document until they do.
struct MirrorConflictResolutionSheet: View {
    let conflict: MirrorConflict
    let onResolve: (MirrorConflict.Resolution) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: MirrorConflict.Resolution?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            comparison
            Divider()
            footer
        }
        .frame(width: 760, height: 520)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resolve conflict")
                .font(.headline)
            Text(conflict.documentTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !conflict.differsInBody {
                Text("The text is identical — only the metadata differs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Comparison

    private var comparison: some View {
        HStack(spacing: 0) {
            versionColumn(
                title: "In Logue",
                subtitle: "The version you have been editing",
                body: conflict.appBody,
                resolution: .keepApp
            )
            Divider()
            versionColumn(
                title: "On disk",
                subtitle: conflict.fileURL.lastPathComponent,
                body: conflict.fileBody,
                resolution: .keepFile
            )
        }
    }

    private func versionColumn(
        title: String,
        subtitle: String,
        body: String,
        resolution: MirrorConflict.Resolution
    ) -> some View {
        let isChosen = choice == resolution

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(isChosen ? "Selected" : "Keep this") {
                    choice = resolution
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isChosen ? AppThemeConstants.accent : nil)
            }

            ScrollView {
                Text(body.isEmpty ? "(empty)" : body)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(isChosen ? 0.12 : 0.06))
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Reveal file in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([conflict.fileURL])
            }
            .controlSize(.small)

            Spacer()

            Button("Decide later") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Keep selected version") {
                guard let choice else { return }
                onResolve(choice)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(choice == nil)
        }
        .padding(16)
    }
}
