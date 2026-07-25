import Foundation

/// Validation for a per-document icon.
///
/// The icon is user-supplied text rendered in lists and titles, and it is embedded
/// in LLM prompts alongside the document title. Validation is therefore strict:
/// exactly one grapheme, no control characters, or nothing at all.
enum DocumentIcon {
    /// Maximum graphemes allowed. One, so an icon cannot become a label.
    static let maxGraphemes = 1

    /// Returns a safe icon, or `nil` to clear it.
    ///
    /// Rejects rather than truncates over-long input — trimming could split a
    /// multi-scalar emoji into a broken fragment.
    static func sanitised(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Category `Cc` only — deliberately NOT `CharacterSet.controlCharacters`,
        // which also covers `Cf` (format) and would reject the zero-width joiner
        // that composes emoji like 👩‍💻.
        let hasControlCharacter = trimmed.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control
        }
        guard !hasControlCharacter else { return nil }
        guard trimmed.count <= maxGraphemes else { return nil }

        return trimmed
    }
}
