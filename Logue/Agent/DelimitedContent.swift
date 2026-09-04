import Foundation

/// Putting text the app did not write into a prompt, as content rather than instruction.
///
/// The project rule is that anything from outside — a transcript, a document, a server's
/// reply, a skill someone imported — is wrapped in a delimiter before it reaches a model.
/// The rule that is easy to forget is the second half: **the payload must not be able to
/// close the region it is inside.** A payload containing its own closing tag ends its quoted
/// region, and everything after it reads as something Logue said.
///
/// This was written twice before it was written once — `MCPToolOutput` had a copy, and the
/// skills work needed the same thing. A control that exists in two places is a control that
/// gets fixed in one.
enum DelimitedContent {
    /// Wraps `raw` in `<tag>…</tag>`, bounded, stripped, and unable to end its own region.
    ///
    /// - Parameters:
    ///   - maxCharacters: the payload budget. Truncation is announced, because a model handed
    ///     a cut-off list with no notice reports it as a complete one.
    static func wrap(_ raw: String, in tag: String, maxCharacters: Int) -> String {
        let bounded = bound(neutralise(strip(raw), tag: tag), to: maxCharacters)
        return "<\(tag)>\n\(bounded)\n</\(tag)>"
    }

    /// Removes control characters, keeping the whitespace that carries meaning.
    ///
    /// Tab, newline and carriage return survive: in a body of text they are structure, not
    /// noise. Everything below them is neither.
    static func strip(_ value: String) -> String {
        value.filter { character in
            guard let ascii = character.asciiValue else { return true }
            return ascii == 9 || ascii == 10 || ascii == 13 || ascii >= 32
        }
    }

    /// Stops the payload closing — or reopening — the region it is inside.
    ///
    /// Both delimiters, not only the closing one: an opening tag inside the payload lets a
    /// reader disagree about where the region starts, which is the same failure approached
    /// from the other end.
    static func neutralise(_ value: String, tag: String) -> String {
        value
            .replacingOccurrences(of: "</\(tag)>", with: "<\\/\(tag)>")
            .replacingOccurrences(of: "<\(tag)>", with: "<\\\(tag)>")
    }

    /// Truncated payloads say so.
    static let truncationNotice = "\n…[truncated by Logue]"

    static func bound(_ value: String, to maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters)) + truncationNotice
    }
}
