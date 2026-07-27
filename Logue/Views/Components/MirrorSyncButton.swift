import SwiftUI

/// Toolbar control showing mirror status and triggering a manual sync.
///
/// Hidden entirely when mirroring is off, so the toolbar carries nothing for a
/// feature the user has not enabled. When conflicts exist it turns orange and says
/// so — an unresolved conflict is the one state worth interrupting for.
struct MirrorSyncButton: View {
    @State private var mirror = MarkdownMirror.shared

    var body: some View {
        if mirror.isEnabled {
            Button(action: sync) {
                HStack(spacing: 5) {
                    icon
                    Text(label)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .disabled(mirror.state.isSyncing)
            .help(helpText)
            .accessibilityLabel(accessibilityText)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var icon: some View {
        switch mirror.state {
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
        case .idle, .off:
            Image(systemName: hasConflicts ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                .font(.caption)
        }
    }

    private var label: String {
        switch mirror.state {
        case let .syncing(completed, total):
            total > 0 ? "Syncing \(completed)/\(total)" : "Syncing"
        case .idle, .off:
            hasConflicts ? conflictLabel : "Sync"
        }
    }

    private var conflictLabel: String {
        let count = mirror.conflicts.count
        return count == 1 ? "1 conflict" : "\(count) conflicts"
    }

    /// Orange while syncing or when conflicts are waiting; secondary at rest, so the
    /// toolbar is calm when there is nothing to act on.
    private var tint: Color {
        hasConflicts || mirror.state.isSyncing ? .orange : .secondary
    }

    private var hasConflicts: Bool {
        !mirror.conflicts.isEmpty
    }

    private var helpText: String {
        if hasConflicts {
            return "Some documents were edited both in Logue and on disk. Open them to resolve."
        }
        if let last = mirror.lastSyncedAt {
            return "Markdown mirror — last synced \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Sync the markdown mirror now"
    }

    private var accessibilityText: String {
        hasConflicts ? "Markdown mirror: \(conflictLabel)" : "Sync markdown mirror"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: - Action

    private func sync() {
        // Yielded to the next runloop turn so the button's disabled state and the
        // progress label render before the pass begins.
        Task { @MainActor in
            mirror.syncAll()
        }
    }
}
