import AppKit
import SwiftUI

/// Phase A0: dedicated privacy surface. Surfaces encryption status, data
/// location with "Reveal in Finder", and the plain-English permission summary
/// (with a hand-off to System Settings when the user wants to revoke).
struct PrivacySettingsTab: View {
    @State private var storage = DocumentStorage.shared
    @Environment(DocumentStore.self) private var documentStore
    @State private var taskStore = TaskStore.shared
    @Environment(SpaceStore.self) private var spaceStore
    @State private var showingEnableWarning = false
    @State private var showingDisableConfirmation = false
    @State private var storageError: String?
    @State private var dataDirectory: URL = Self.dataDirectory()
    @State private var showEraseConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                encryptionSection
                Divider()
                dataLocationSection
                Divider()
                markdownStorageSection
                Divider()
                BrowserExtensionSection()
                Divider()
                permissionsSection
                Divider()
                eraseSection
            }
            .padding(20)
        }
    }

    // MARK: - Plain Markdown Storage

    /// Opt-in plain-markdown storage.
    ///
    /// Under Privacy because that is the real trade: documents stop being encrypted and
    /// become readable by anything on the Mac. Presenting it as a convenience feature
    /// would bury the part the user needs to weigh.
    private var markdownStorageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plain Markdown Storage")
                .font(.headline)

            Text("Store documents as ordinary .md files in a Logue folder in your home folder, so you can "
                + "edit them in another app, track them in git, or let AI agents read them. "
                + "Meetings, transcripts and audio always stay encrypted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if storage.mode.isMarkdown {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(DocumentStorage.markdownRootURL.path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [DocumentStorage.markdownRootURL]
                        )
                    }
                    .controlSize(.small)
                    Button("Turn Off") { showingDisableConfirmation = true }
                        .controlSize(.small)
                }

                Label("Documents in this folder are not encrypted.", systemImage: "lock.open")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Button("Turn On…") { showingEnableWarning = true }
                    .controlSize(.small)
            }

            if let error = storageError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showingEnableWarning) {
            MarkdownStorageWarningSheet { enableMarkdownStorage() }
        }
        .confirmationDialog(
            "Turn off plain markdown storage?",
            isPresented: $showingDisableConfirmation,
            titleVisibility: .visible
        ) {
            // Moving the folder to the Trash is the first and default choice deliberately. A
            // folder left behind looks like the library but is not one: nothing writes to it and
            // nothing reads it, so an edit made there silently does nothing. Keeping it is still
            // offered for anyone who tracks it in git or wants to move it themselves.
            Button("Turn Off and Move Folder to Trash") { disableMarkdownStorage(retiringFolder: true) }
            Button("Turn Off and Keep Folder") { disableMarkdownStorage(retiringFolder: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your documents move back into Logue's encrypted storage. The Logue folder is no "
                + "longer read or written after this, so leaving it behind means edits made there "
                + "do nothing. Moving it to the Trash keeps it recoverable.")
        }
    }

    private func enableMarkdownStorage() {
        storageError = nil
        do {
            try storage.switchToMarkdown(
                documents: documentStore.documents,
                spaces: spaceStore.spaces,
                tasks: taskStore.tasks
            )
        } catch {
            // Nothing was changed: the switch verifies every file before flipping.
            storageError = error.localizedDescription
        }
    }

    private func disableMarkdownStorage(retiringFolder: Bool) {
        storageError = nil

        do {
            let restored = try storage.switchToEncrypted(
                knownSpaces: spaceStore.spaces,
                retiringFolder: retiringFolder,
                // What the folder has to account for. Fewer means files are missing rather than
                // deleted, and switching would prune the encrypted copies of the difference.
                expectedDocumentCount: documentStore.activeDocuments.count
            )

            // The switch already re-encrypted these; adopting them now means the list on
            // screen matches what encrypted storage holds before the folder can be trashed.
            taskStore.replaceAll(with: storage.restoredTasks)

            Task {
                // In this order, and awaited: the folder is the only copy of anything created while
                // the setting was on, so it cannot go to the Trash until every document is confirmed
                // written to encrypted storage. This used to be an unawaited task with log-only
                // failures, running *after* the folder had already been trashed.
                await documentStore.adoptAfterStorageSwitch(restored)
                await documentStore.awaitPendingSaves()

                guard retiringFolder else { return }
                do {
                    try storage.retireFolderAfterReEncryption(of: restored)
                } catch {
                    storageError = error.localizedDescription
                }
            }
        } catch {
            // Nothing was changed: the switch refuses before it reads rather than part-way through.
            storageError = error.localizedDescription
        }
    }

    // MARK: - Encryption

    private var encryptionSection: some View {
        sectionCard(title: "Encryption") {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AES-256-GCM at rest")
                        .font(.callout.weight(.semibold))
                    Text(encryptionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Reads the mode rather than asserting the default.
    ///
    /// The flat claim sat directly above the section explaining that documents are *not* encrypted
    /// once this setting is on — a contradiction on the one tab where a user goes to check exactly
    /// this.
    private var encryptionDetail: String {
        if storage.mode.isMarkdown {
            return "Conversations and meetings are encrypted on disk, and the key never leaves this "
                + "Mac. Documents are not: plain markdown storage is on, so they are readable files "
                + "in your home folder."
        }
        return "Conversations, meetings, and documents are encrypted on disk. The key never leaves this Mac."
    }

    // MARK: - Data location

    private var dataLocationSection: some View {
        sectionCard(title: "Data location") {
            VStack(alignment: .leading, spacing: 8) {
                Text(dataDirectory.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectory.path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Permissions summary

    private var permissionsSection: some View {
        sectionCard(title: "Permissions") {
            VStack(alignment: .leading, spacing: 6) {
                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    detail: "Used while recording meetings — never sent off-device."
                )
                permissionRow(
                    icon: "calendar",
                    title: "Calendar",
                    detail: "Read upcoming events, create / edit / delete on request."
                )
                permissionRow(
                    icon: "checklist",
                    title: "Reminders",
                    detail: "Read + write reminders on request."
                )
                permissionRow(
                    icon: "person.crop.circle",
                    title: "Contacts",
                    detail: "Look up names + email addresses for drafting messages."
                )
                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Required for the ⌘⌃I inline writing assistant to read selected text."
                )
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings → Privacy", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Erase

    private var eraseSection: some View {
        sectionCard(title: "Reset") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Erase all on-device Logue data — conversations, meetings, documents, and the vector store. Cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showEraseConfirm = true
                } label: {
                    Label("Erase all data…", systemImage: "trash")
                }
                .controlSize(.small)
                .alert("Erase all Logue data?", isPresented: $showEraseConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Erase", role: .destructive) { eraseAllData() }
                } message: {
                    Text("This will delete all conversations, meetings, and documents from this Mac. It cannot be undone.")
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
            content()
        }
    }

    private static func dataDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        return base.appending(path: "Logue", directoryHint: .isDirectory)
    }

    private func eraseAllData() {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dataDirectory.path) {
                try fm.removeItem(at: dataDirectory)
            }

            // The unencrypted folder too, or "All data erased" is a false claim: with plain markdown
            // storage on, every document is a readable file outside this directory, and the setting
            // itself is in UserDefaults so the next launch would read them straight back in.
            if storage.mode.isMarkdown {
                try storage.eraseMarkdownFolder()
            }

            ToastCenter.shared.show("All data erased — restart Logue", kind: .warning)
        } catch {
            ToastCenter.shared.show("Couldn't erase data", kind: .warning)
        }
    }
}
