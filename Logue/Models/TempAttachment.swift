import Foundation

/// A user-attached file dropped onto the agent input bar. Per-conversation only —
/// not indexed or persisted across launches (matches Sidekick's `TemporaryResource`
/// semantics). Text is pre-extracted before send so the agent loop never blocks on
/// disk I/O.
struct TempAttachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case plainText
        case pdf
        case image
        case other
    }

    let id: UUID
    let kind: Kind
    /// User-visible filename (e.g. "spec.pdf").
    let displayName: String
    /// Extracted plaintext for `.plainText` / `.pdf`. Empty for `.image` / `.other`.
    /// Capped at `TempAttachment.maxExtractedChars` upstream.
    let extractedText: String
    /// SF Symbol name to render in the chip UI.
    let iconName: String

    /// Hard cap on extracted text per attachment. Stops a single dropped book from
    /// blowing the agent's context window.
    static let maxExtractedChars = 16000

    init(
        id: UUID = .init(),
        kind: Kind,
        displayName: String,
        extractedText: String,
        iconName: String
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.extractedText = extractedText
        self.iconName = iconName
    }

    /// Builds the `<attached_file>` block injected into the user turn so the LLM
    /// sees the content as user-supplied context. `kind == .image` returns an empty
    /// string today (image OCR is a future addition).
    func injectionBlock() -> String {
        guard !extractedText.isEmpty else { return "" }
        return """

        <attached_file name="\(sanitizeName(displayName))" kind="\(kind.rawValue)">
        \(extractedText)
        </attached_file>
        """
    }

    /// Strips characters that would break XML attribute parsing if the LLM tries
    /// to round-trip the wrapper. Also drops control chars + newlines per
    /// CLAUDE.md — a filename containing literal `\n` would inject a newline
    /// inside the `name="..."` attribute and corrupt the prompt.
    private func sanitizeName(_ name: String) -> String {
        name.filter { !$0.isNewline && $0.asciiValue != 0 }
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
    }
}
