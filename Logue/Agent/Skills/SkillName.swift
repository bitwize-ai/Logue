import Foundation

/// What a skill may be called, and what it is called when you invoke it.
///
/// A skill is invoked **by name** from a composer, so the name is not decoration — it is the
/// address. That makes it the one field that cannot be free text: two skills sharing an
/// invocation name means one of them can never be reached, and a name that cannot be typed
/// into a single composer token is a skill that cannot be invoked at all.
///
/// So there are two names, deliberately. The **title** is what the user writes and reads —
/// any text, any script, spaces and punctuation included. The **invocation** is derived from
/// it: lowercased, folded to one word, bounded. `Weekly Review` is invoked as
/// `weekly-review`, and the user never has to keep the two in step by hand.
///
/// Deriving rather than asking is the same argument `MCPToolNaming` makes for namespaces: a
/// name the user supplies is a name that can collide with something it should not, and a
/// name that is computed cannot.
enum SkillName {
    /// Longest a title may be. A title is shown in a menu and in a chip.
    static let maxTitleLength = 60

    /// Longest an invocation name may be, so it stays one readable token.
    static let maxInvocationLength = 40

    /// Why a title was refused.
    enum Rejection: Error, Equatable {
        case empty
        case noUsableCharacters
        case duplicate(existingTitle: String)

        var message: String {
            switch self {
            case .empty: "Give the skill a name."
            case .noUsableCharacters:
                "That name has no letters or numbers in it, so there would be no way to type it."
            case let .duplicate(existing): "“\(existing)” already uses that name."
            }
        }
    }

    /// The title, cleaned but still the user's words.
    ///
    /// Control and format characters go, because a title is shown in a menu and reaches a
    /// prompt — the same strip `DisplayText` applies to an approval card's target, and for
    /// the same reason.
    static func title(from raw: String) -> String {
        String(DisplayText.singleLine(raw).prefix(maxTitleLength))
    }

    /// The name this skill is invoked by, derived from its title.
    ///
    /// Lowercased; every run of non-alphanumerics becomes a single hyphen; bounded; and
    /// trimmed of leading and trailing hyphens so `— Weekly Review —` does not become
    /// `-weekly-review-`, which reads as a typo rather than a name.
    static func invocation(from title: String) -> String {
        let folded = title.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(folded)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(collapsed.prefix(maxInvocationLength))
    }

    /// Whether a title can be used, given what already exists.
    ///
    /// - Parameter existing: the titles of the other skills. The caller excludes the one
    ///   being edited, because a skill does not collide with itself.
    static func validate(_ raw: String, against existing: [String]) -> Result<String, Rejection> {
        let cleaned = title(from: raw).trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return .failure(.empty) }

        let invocation = invocation(from: cleaned)
        // A title of nothing but punctuation cleans to something non-empty and derives to
        // nothing — there would be no way to invoke it. Refused with the reason, rather than
        // accepted into a skill that can never be reached.
        guard !invocation.isEmpty else { return .failure(.noUsableCharacters) }

        if let clash = existing.first(where: { Self.invocation(from: $0) == invocation }) {
            return .failure(.duplicate(existingTitle: clash))
        }
        return .success(cleaned)
    }
}
