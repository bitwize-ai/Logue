import SwiftUI

/// The five GitHub alert types a callout block can be.
///
/// Deliberately closed. An unrecognised marker such as `> [!BANANA]` is not a callout at
/// all — the serializer leaves it to be parsed as an ordinary block quote, which is what
/// GitHub does with it too, and which keeps the round-trip honest: a type we cannot name is
/// a type we cannot write back.
enum CalloutKind: String, CaseIterable, Codable, Sendable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    /// Parses the marker text between the brackets, e.g. `NOTE` from `> [!NOTE]`.
    ///
    /// Case-insensitive on the way in because editors and people write `[!note]` too, but
    /// `rawValue` — always upper case — is what gets written back, so a document normalises
    /// to the spelling GitHub renders.
    init?(marker: String) {
        let upper = marker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let match = CalloutKind(rawValue: upper) else { return nil }
        self = match
    }

    /// Title shown when the callout has no title of its own. Matches GitHub's rendering.
    var defaultTitle: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .note: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .important: "exclamationmark.bubble.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .caution: "exclamationmark.octagon.fill"
        }
    }

    /// Accent used for the icon, the title and the leading rule. Follows GitHub's alert
    /// palette; system colours rather than fixed values so both appearances stay legible.
    var accent: Color {
        switch self {
        case .note: .blue
        case .tip: .green
        case .important: .purple
        case .warning: .orange
        case .caution: .red
        }
    }
}
