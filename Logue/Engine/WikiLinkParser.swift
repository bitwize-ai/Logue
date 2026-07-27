import Foundation

// MARK: - WikiLink

/// A `[[target]]` or `[[target|display text]]` reference found in a document body.
///
/// `range` is a UTF-16 `NSRange` covering the whole reference including the
/// delimiters, so it can be handed straight to `NSAttributedString` styling or an
/// `NSTextView` without conversion. Callers reading neighbouring characters must
/// convert with `Range(_:in:)` rather than indexing a `String` by these offsets.
struct WikiLink: Equatable, Sendable {
    /// The link target — a document or meeting title. Whitespace-trimmed, never empty.
    let target: String
    /// Optional text shown in place of the target, from the `|` alias form.
    let displayText: String?
    /// UTF-16 range of the whole `[[...]]` reference in the source text.
    let range: NSRange

    /// What should be rendered for this link.
    var resolvedText: String {
        displayText ?? target
    }
}

// MARK: - Parser

/// Extracts wikilinks from document text.
///
/// Deliberately independent of any store, so it can be unit-tested and reused by
/// the editor, the link index, and search without pulling in persistence.
enum WikiLinkParser {
    /// `[[` then any run without newlines or brackets, then `]]`.
    ///
    /// Excluding `[` and `]` from the body keeps a malformed `[[a]]b]]` from
    /// swallowing the trailing delimiters, and excluding newlines confines a link
    /// to one line — an unclosed `[[` should not consume the rest of the document.
    private static let pattern = "\\[\\[([^\\[\\]\n]*)\\]\\]"

    private static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    /// All links in `text`, in document order.
    static func links(in text: String) -> [WikiLink] {
        guard !text.isEmpty, let regex else { return [] }

        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: text, range: full).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let bodyRange = match.range(at: 1)
            guard bodyRange.location != NSNotFound else { return nil }

            return makeLink(body: nsText.substring(with: bodyRange), range: match.range)
        }
    }

    /// Distinct targets in `text`, compared case-insensitively.
    ///
    /// Titles are matched case-insensitively elsewhere in the app, so a document
    /// referenced as both `[[Alpha]]` and `[[alpha]]` is one target, not two.
    static func uniqueTargets(in text: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for link in links(in: text) {
            let key = link.target.lowercased()
            if seen.insert(key).inserted {
                ordered.append(link.target)
            }
        }
        return ordered
    }

    // MARK: - Private

    /// Splits a link body into target and optional display text.
    /// Returns `nil` when the target is empty, so `[[]]` is not treated as a link.
    private static func makeLink(body: String, range: NSRange) -> WikiLink? {
        // Only the first `|` separates; a display text may itself contain pipes.
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)

        let target = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }

        var displayText: String?
        if parts.count > 1 {
            let trimmed = String(parts[1]).trimmingCharacters(in: .whitespaces)
            displayText = trimmed.isEmpty ? nil : trimmed
        }

        return WikiLink(target: target, displayText: displayText, range: range)
    }
}
