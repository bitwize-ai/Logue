import Foundation

/// An in-progress `[[` link at the caret.
///
/// Ranges are UTF-16 `NSRange`s so they can be handed straight to `NSTextView`.
/// Callers reading neighbouring characters must convert via `Range(_:in:)` rather
/// than indexing a `String` with these offsets.
struct WikiLinkCompletion: Equatable, Sendable {
    /// What the user has typed after `[[`, up to the caret. May be empty.
    let query: String
    /// The range to overwrite when a suggestion is chosen — the `[[`, the partial
    /// query, and a trailing `]]` when one is already present.
    let replacementRange: NSRange

    private static let opening = "[["
    private static let closing = "]]"

    /// Detects an in-progress link at `cursor`.
    ///
    /// Returns `nil` when the caret is not inside an unclosed `[[`, when a newline
    /// intervenes (a link may not span lines), or when the user has typed a `|` and
    /// is therefore writing display text rather than choosing a target.
    static func atCursor(in text: String, cursor: Int) -> WikiLinkCompletion? {
        let nsText = text as NSString
        guard cursor >= 0, cursor <= nsText.length else { return nil }

        let beforeCursor = NSRange(location: 0, length: cursor)
        let openRange = nsText.range(of: opening, options: .backwards, range: beforeCursor)
        guard openRange.location != NSNotFound else { return nil }

        let queryStart = NSMaxRange(openRange)
        let query = nsText.substring(with: NSRange(location: queryStart, length: cursor - queryStart))

        // A link stays on one line, and a pipe means the target is already chosen.
        guard !query.contains("\n"), !query.contains("|") else { return nil }
        // A closing pair between the opening and the caret means that link is done.
        guard !query.contains(closing) else { return nil }

        return WikiLinkCompletion(
            query: query,
            replacementRange: replacementRange(in: nsText, from: openRange.location, cursor: cursor)
        )
    }

    /// The text inserted when a suggestion is chosen.
    ///
    /// Strips the characters that carry meaning in link syntax so a title containing
    /// `[`, `]`, or `|` cannot produce an unparseable or aliased link, and flattens
    /// newlines because a link may not span lines.
    static func insertionText(for title: String) -> String {
        var sanitised = title
        for token in ["[", "]", "|"] {
            sanitised = sanitised.replacingOccurrences(of: token, with: "")
        }
        sanitised = sanitised
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return "\(opening)\(sanitised)\(closing)"
    }

    // MARK: - Private

    /// Extends the range past an existing `]]` immediately after the caret, so
    /// completing a link the user already closed does not leave stray brackets.
    private static func replacementRange(in nsText: NSString, from start: Int, cursor: Int) -> NSRange {
        var end = cursor
        let remaining = nsText.length - cursor
        if remaining >= closing.count {
            let candidate = NSRange(location: cursor, length: closing.count)
            if nsText.substring(with: candidate) == closing {
                end = NSMaxRange(candidate)
            }
        }
        return NSRange(location: start, length: end - start)
    }
}
