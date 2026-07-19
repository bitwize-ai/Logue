import SwiftUI

/// On-device privacy badge shown across the app (recording bar, export panel, sidebar, settings, empty states).
///
/// Usage:
/// ```
/// PrivacyBadge("All transcription happens on-device. Nothing leaves your Mac.")
/// PrivacyBadge("On-device", style: .compact)
/// ```
struct PrivacyBadge: View {
    let text: String
    var style: Style = .standard

    enum Style {
        /// Multi-line caption-sized text beside the shield icon.
        case standard
        /// Single-line compact badge (e.g. recording bar).
        case compact
        /// Two-line badge with title and subtitle.
        case detailed(title: String)
    }

    init(_ text: String, style: Style = .standard) {
        self.text = text
        self.style = style
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(style.isCompact ? .caption2 : .caption)
                .foregroundColor(AppThemeConstants.success)

            switch style {
            case .standard:
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .compact:
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case let .detailed(title):
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                    Text(text)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy: \(text)")
    }
}

extension PrivacyBadge.Style {
    var isCompact: Bool {
        if case .compact = self {
            return true
        }
        return false
    }
}
