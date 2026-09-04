import Foundation

/// Turning a string that came from somewhere else into one line it is safe to show.
///
/// Two places need exactly this — the sentence on an approval card and the argument line on
/// a tool card — and both show text the app did not write: a document title, a filesystem
/// path, an argument a model produced. They had a copy each, which is one copy too many for
/// something that is partly a security control.
enum DisplayText {
    /// One line, with everything that could make that line lie taken out.
    ///
    /// **Control and format characters go first**, and that is the half that matters. A title
    /// is not always something the user typed: it can arrive in a `.md` file dropped into the
    /// markdown folder, or from a call a prompt-injected model made. A bidirectional override
    /// (U+202E) reverses the display of everything after it, so `Delete “report.txt”` can be
    /// made to read as a different file — and on an approval card that sits directly above a
    /// Touch ID prompt. `CharacterSet.controlCharacters` is Unicode categories Cc *and* Cf,
    /// which is what makes it the right set rather than merely a plausible one.
    ///
    /// Whitespace is then collapsed, so a multi-paragraph value looks as truncated as it is
    /// rather than like a short one, and a newline cannot split a sentence in half and leave
    /// the verb sitting alone above Approve.
    static func singleLine(_ value: String) -> String {
        // Whitespace is exempted from the strip and handled by the split below, because a
        // newline is itself a control character (U+000A is Cc). Removing it here rather than
        // splitting on it would run the words either side of it together — `first\nsecond`
        // becoming `firstsecond`, which reads as a different value rather than a flattened
        // one. So: take out the controls that carry no meaning, then let the split turn the
        // ones that do into a single space.
        let scrubbed = value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return String(String.UnicodeScalarView(scrubbed))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cuts to `limit`, marking that something was cut.
    ///
    /// The ellipsis is inside the budget rather than added to it, so the result is never
    /// longer than the caller asked for.
    static func clamp(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        guard limit > 1 else { return String(value.prefix(limit)) }
        return String(value.prefix(limit - 1)) + "…"
    }
}
