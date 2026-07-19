import SwiftUI

/// Bottom-center pill that appears when the chat scroll view has been
/// scrolled up >120 pt while a stream is in progress. Tapping it scrolls
/// back to the bottom and re-pins to "latest".
///
/// Visibility is owned by the parent — this view just renders.
struct JumpToLatestPill: View {
    var unreadCount: Int = 0
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.accentColor)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.downArrow, modifiers: [.command])
        .accessibilityLabel("Jump to latest message")
    }

    private var label: String {
        if unreadCount > 0 {
            return "\(unreadCount) new"
        }
        return "Jump to latest"
    }
}
