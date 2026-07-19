import AppKit
import SwiftUI

/// Phase A0: dedicated privacy surface. Surfaces encryption status, data
/// location with "Reveal in Finder", and the plain-English permission summary
/// (with a hand-off to System Settings when the user wants to revoke).
struct PrivacySettingsTab: View {
    @State private var dataDirectory: URL = Self.dataDirectory()
    @State private var showEraseConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                encryptionSection
                Divider()
                dataLocationSection
                Divider()
                permissionsSection
                Divider()
                eraseSection
            }
            .padding(20)
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
                    Text("Conversations, meetings, and documents are encrypted on disk. The key never leaves this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
            ToastCenter.shared.show("All data erased — restart Logue", kind: .warning)
        } catch {
            ToastCenter.shared.show("Couldn't erase data", kind: .warning)
        }
    }
}
