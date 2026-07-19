import AppKit
import Foundation

/// Wraps NSSpellChecker to produce [Suggestion] with always-valid textRange.
/// Spelling and grammar results are available synchronously on the main thread
/// (NSSpellChecker does its work on-device in < 50 ms for typical documents).
struct InlineSpellEngine {
    /// Per-document tag lets NSSpellChecker remember "Ignore Word" lists.
    let docTag = NSSpellChecker.uniqueSpellDocumentTag()

    // MARK: - Window Calculation

    /// Compute the window NSRange for a given cursor offset.
    func windowRange(for text: String, cursorOffset: Int, windowSize: Int = AppConstants.LLMDefaults.contextWindowSize) -> NSRange {
        let nsText = text as NSString
        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }
        let half = windowSize / 2
        let rawStart = max(0, cursorOffset - half)
        let start = min(rawStart, max(0, nsText.length - windowSize))
        let length = min(windowSize, nsText.length - start)
        return NSRange(location: start, length: length)
    }

    // MARK: - Public API

    /// Check only a focused window of the text (around `cursorOffset`), returning
    /// suggestions whose `textRange` values are relative to the **full** string.
    func checkFocused(_ text: String, cursorOffset: Int, windowSize: Int = AppConstants.LLMDefaults.contextWindowSize) -> [Suggestion] {
        guard !text.isEmpty else { return [] }

        let window = windowRange(for: text, cursorOffset: cursorOffset, windowSize: windowSize)
        let nsText = text as NSString
        let substring = nsText.substring(with: window)

        let localSuggestions = check(substring)

        // Shift textRange back to full-document coordinates
        return localSuggestions.map { suggestion in
            Suggestion(
                id: suggestion.id,
                type: suggestion.type,
                original: suggestion.original,
                replacement: suggestion.replacement,
                explanation: suggestion.explanation,
                confidence: suggestion.confidence,
                textRange: NSRange(location: suggestion.textRange.location + window.location, length: suggestion.textRange.length)
            )
        }
    }

    // swiftlint:disable:next function_body_length
    func check(_ text: String) -> [Suggestion] {
        guard !text.isEmpty else { return [] }

        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Force English so short text / mixed content is reliably spell-checked.
        let language = "en"

        var suggestions: [Suggestion] = []

        // 1. Find all misspelled words using checkSpelling (iterative, most reliable).
        var searchOffset = 0
        while searchOffset < nsText.length {
            let searchRange = NSRange(location: searchOffset, length: nsText.length - searchOffset)
            let misspelled = checker.checkSpelling(
                of: text,
                startingAt: searchRange.location,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: docTag,
                wordCount: nil
            )

            guard misspelled.length > 0 else { break }

            let word = nsText.substring(with: misspelled)
            let guesses = checker.guesses(
                forWordRange: misspelled,
                in: text,
                language: language,
                inSpellDocumentWithTag: docTag
            ) ?? []
            let best = guesses.first

            suggestions.append(Suggestion(
                id: UUID(),
                type: .spelling,
                original: word,
                replacement: best ?? word,
                explanation: best.map { "Did you mean \"\($0)\"?" }
                    ?? "Possible spelling error.",
                confidence: best != nil ? 0.90 : 0.70,
                textRange: misspelled
            ))

            searchOffset = NSMaxRange(misspelled)
        }

        // 2. Find grammar issues using checkGrammar (iterative, most reliable).
        var grammarOffset = 0
        while grammarOffset < nsText.length {
            var details: NSArray?
            let grammarRange = checker.checkGrammar(
                of: text,
                startingAt: grammarOffset,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: docTag,
                details: &details
            )

            guard grammarRange.length > 0 else { break }

            let phrase = nsText.substring(with: grammarRange)

            // Each detail dict can contain a sub-range and description.
            if let detailDicts = details as? [[String: Any]], !detailDicts.isEmpty {
                for detail in detailDicts {
                    let desc = (detail[NSGrammarUserDescription] as? String)
                        ?? "Possible grammar issue."

                    // Grammar details may specify a sub-range within the grammar range.
                    var detailRange = grammarRange
                    if let subRange = detail[NSGrammarRange] as? NSValue {
                        let sub = subRange.rangeValue
                        // Sub-range is relative to the grammar range.
                        detailRange = NSRange(
                            location: grammarRange.location + sub.location,
                            length: sub.length
                        )
                    }

                    // Get replacement from corrections array if available.
                    // Skip grammar issues that have no actionable correction.
                    let corrections = detail[NSGrammarCorrections] as? [String]
                    guard let replacement = corrections?.first else { continue }

                    // Avoid duplicating spelling suggestions.
                    let alreadyFound = suggestions.contains {
                        $0.textRange.location == detailRange.location &&
                            $0.textRange.length == detailRange.length
                    }
                    guard !alreadyFound else { continue }

                    suggestions.append(Suggestion(
                        id: UUID(),
                        type: .grammar,
                        original: nsText.substring(with: detailRange),
                        replacement: replacement,
                        explanation: desc,
                        confidence: 0.80,
                        textRange: detailRange
                    ))
                }
            }

            grammarOffset = NSMaxRange(grammarRange)
        }

        return suggestions
    }

    /// Call when the associated document is closed to release NSSpellChecker memory.
    func close() {
        NSSpellChecker.shared.closeSpellDocument(withTag: docTag)
    }
}
