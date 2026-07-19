import SwiftUI

/// Inline Approve / Reject buttons rendered inside a tool card when the agent
/// is awaiting user confirmation for a tool call. The Approve button's icon and
/// tint adjust based on `clearance` — `.dangerous` uses a fingerprint icon and a
/// red tint to signal that approving will trigger a Touch ID prompt.
struct ToolApprovalButtons: View {
    let toolCallID: UUID
    let conversationID: UUID
    /// The clearance tier captured when the approval card was posted. `.dangerous`
    /// shows a Touch ID variant; `.sensitive` shows the standard Approve.
    var clearance: ToolClearance = .sensitive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if clearance == .dangerous {
                HStack(spacing: 4) {
                    Image(systemName: "touchid")
                        .font(.caption)
                    Text("Touch ID required to approve")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    AgentCoordinator.shared.reject(toolCallID: toolCallID, in: conversationID)
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)

                Button {
                    AgentCoordinator.shared.approve(toolCallID: toolCallID, in: conversationID)
                } label: {
                    Label(approveLabel, systemImage: approveIcon)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(approveTint)
            }
        }
    }

    private var approveLabel: String {
        clearance == .dangerous ? "Approve with Touch ID" : "Approve"
    }

    private var approveIcon: String {
        clearance == .dangerous ? "touchid" : "checkmark"
    }

    private var approveTint: Color {
        clearance == .dangerous ? .red : .orange
    }
}
