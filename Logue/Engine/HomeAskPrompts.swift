import Foundation

/// The sentence a Home card drops into the chat input when the user taps its ✦.
///
/// Pure on purpose: no view, no store, no inference. The card knows *which* object the
/// user pointed at; this decides what asking about it should say. Keeping the two apart
/// is what makes the wording testable, and it is the only reason a title's sanitization
/// can be proven rather than assumed.
///
/// These sentences are not wrapped in XML delimiters. That rule exists for injecting
/// content *blocks* — transcripts, document bodies — where the boundary between
/// instruction and content has to be unambiguous. What this builds is an ordinary user
/// message containing a quoted title, identical to something the user could type by
/// hand, and delimiters would be visible in the input box. Sanitizing the title is what
/// actually matters here.
enum HomeAskPrompts {
    /// Longest title we will quote back into a message.
    static let maxTitleLength = 120

    /// Trims a user-authored title down to something safe to quote.
    ///
    /// Stripping runs before truncation, so a title padded with control characters
    /// cannot push its real content past the limit.
    static func sanitize(_ title: String, fallback: String) -> String {
        let stripped = title.filter { !isDisallowed($0) }
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return fallback }
        let truncated = String(trimmed.prefix(maxTitleLength))
        let tidied = truncated.trimmingCharacters(in: .whitespaces)
        return tidied.isEmpty ? fallback : tidied
    }

    /// Newlines and control characters both go. A newline would let a title open a new
    /// instruction line inside the message; the wider control-character sweep is cheap
    /// and closes the same door for the non-printing characters either side of it.
    private static func isDisallowed(_ character: Character) -> Bool {
        if character.isNewline {
            return true
        }
        return character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    // MARK: - Sentences

    static func meeting(title: String, isSummarized: Bool) -> String {
        let name = sanitize(title, fallback: "Untitled meeting")
        if isSummarized {
            return "What were the decisions in “\(name)”?"
        }
        return "Summarize the meeting “\(name)” and pull out the action items."
    }

    static func document(title: String) -> String {
        let name = sanitize(title, fallback: "Untitled document")
        return "Help me continue writing “\(name)”."
    }

    static func actionItem(title: String) -> String {
        let name = sanitize(title, fallback: "this action item")
        return "What do I need to do for “\(name)”, and what is the context "
            + "from the meeting it came from?"
    }

    static func calendarEvent(title: String) -> String {
        let name = sanitize(title, fallback: "this meeting")
        return "Prepare me for “\(name)” — what happened last time and what is still outstanding?"
    }
}
