import Foundation

/// The `==highlighted text==` inline mark.
///
/// This is not CommonMark, so `swift-markdown` treats the delimiters as literal
/// text. That works in our favour: the delimiters survive a parse/serialize round
/// trip untouched, and this type owns detecting and toggling them.
enum HighlightMark {
    static let delimiter = "=="

    private static let delimiterLength = 2

    /// Matches `==content==` where the content is non-empty and stays on one line.
    /// `[^=\n]` for the first and last content characters prevents matching the
    /// empty `====` case or bleeding across an adjacent mark.
    private static let pattern = "==([^=\n](?:[^\n]*?[^=\n])?)=="

    /// Ranges of complete highlight marks, delimiters included.
    static func ranges(in text: String) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: full).map(\.range)
    }

    /// Ranges of the highlighted content, delimiters excluded — use this when
    /// applying a background style so the delimiters are not painted.
    static func contentRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: full).compactMap { match in
            match.numberOfRanges > 1 ? match.range(at: 1) : nil
        }
    }

    /// Adds or removes highlight delimiters around `range`.
    ///
    /// Returns the text unchanged for an empty or out-of-bounds range, so callers
    /// can pass a raw selection without pre-validating it.
    static func toggled(in text: String, range: NSRange) -> String {
        let nsText = text as NSString
        guard range.length > 0,
              range.location >= 0,
              NSMaxRange(range) <= nsText.length
        else { return text }

        // Case 1: the selection sits immediately inside an existing pair.
        if let unwrapped = unwrappingSurroundingDelimiters(in: nsText, range: range) {
            return unwrapped
        }

        // Case 2: the selection itself spans a complete pair.
        let selected = nsText.substring(with: range)
        if selected.hasPrefix(delimiter),
           selected.hasSuffix(delimiter),
           selected.count > delimiterLength * 2
        {
            let inner = String(selected.dropFirst(delimiterLength).dropLast(delimiterLength))
            return nsText.replacingCharacters(in: range, with: inner)
        }

        // Case 3: plain text — wrap it.
        return nsText.replacingCharacters(in: range, with: delimiter + selected + delimiter)
    }

    private static func unwrappingSurroundingDelimiters(in nsText: NSString, range: NSRange) -> String? {
        let leadingStart = range.location - delimiterLength
        let trailingStart = NSMaxRange(range)
        guard leadingStart >= 0, trailingStart + delimiterLength <= nsText.length else { return nil }

        let leading = NSRange(location: leadingStart, length: delimiterLength)
        let trailing = NSRange(location: trailingStart, length: delimiterLength)
        guard nsText.substring(with: leading) == delimiter,
              nsText.substring(with: trailing) == delimiter
        else { return nil }

        // Delete the trailing pair first so the leading range stays valid.
        let result = NSMutableString(string: nsText)
        result.deleteCharacters(in: trailing)
        result.deleteCharacters(in: leading)
        return result as String
    }
}
