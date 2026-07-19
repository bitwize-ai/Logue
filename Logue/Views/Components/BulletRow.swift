import SwiftUI

/// Colored bullet + text row used in Smart Minutes, digest highlights, and action lists.
///
/// Usage:
/// ```
/// BulletRow(text: "Approved Q2 budget", color: .green)
/// BulletRow(text: "Review contract by Friday", color: .orange, index: 1)
/// BulletRow(text: "Send follow-up email", color: .purple, style: .checkbox)
/// ```
struct BulletRow: View {
    let text: String
    let color: Color
    var style: Style = .bullet
    /// When set, shows a numbered badge instead of a plain bullet.
    var index: Int?

    enum Style {
        case bullet
        case checkbox
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let index {
                Text("\(index)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(color.opacity(AppThemeConstants.activeOpacity))
                    )
                    .padding(.top, 1)
            } else {
                switch style {
                case .bullet:
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                case .checkbox:
                    Image(systemName: "circle")
                        .font(.system(size: 8))
                        .foregroundStyle(color.opacity(0.6))
                        .padding(.top, 4)
                }
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
