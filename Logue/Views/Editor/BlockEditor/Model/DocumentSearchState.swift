import Foundation

// MARK: - Search Match

struct SearchMatch: Identifiable {
    let id = UUID()
    let blockID: BlockID
    /// Non-nil for list/checkbox items to identify which item within the block.
    let itemID: UUID?
    /// Character range within the block's or item's text.
    let range: NSRange

    var target: ReplaceTarget {
        ReplaceTarget(blockID: blockID, itemID: itemID)
    }
}

// MARK: - Replace Target

/// Identifies the single editable string a match lives in — a block's own text, or
/// one item inside a list block.
struct ReplaceTarget: Hashable {
    let blockID: BlockID
    let itemID: UUID?
}

// MARK: - Document Search State

@Observable
final class DocumentSearchState {
    var isActive = false
    var query = ""
    /// Text typed into the replace field; empty is valid (deletes the match).
    var replacement = ""
    /// Whether the replace row is shown in the find bar.
    var isReplaceVisible = false
    var matchCase = false
    var wholeWord = false
    var matches: [SearchMatch] = []
    var currentMatchIndex: Int = 0

    var currentMatch: SearchMatch? {
        guard !matches.isEmpty, matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    var matchCountText: String {
        guard !query.isEmpty else { return "" }
        if matches.isEmpty {
            return "0 results"
        }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    func close() {
        isActive = false
        query = ""
        replacement = ""
        isReplaceVisible = false
        matches = []
        currentMatchIndex = 0
    }

    // MARK: - Replace

    /// Replaces the match at `currentMatchIndex` and refreshes the match list.
    @MainActor
    func replaceCurrent(with replacementText: String, in document: BlockEditorDocument) {
        guard !query.isEmpty, let match = currentMatch else { return }
        apply(ranges: [match.range], replacement: replacementText, to: match.target, in: document)
        search(in: document.blocks)
    }

    /// Replaces every current match. Returns how many were replaced.
    @MainActor
    @discardableResult
    func replaceAll(with replacementText: String, in document: BlockEditorDocument) -> Int {
        guard !query.isEmpty, !matches.isEmpty else { return 0 }
        let replacedCount = matches.count

        // Group by target so each text is rewritten once, and apply each target's
        // ranges from last to first so earlier offsets stay valid when the
        // replacement has a different length than the query.
        var rangesByTarget: [ReplaceTarget: [NSRange]] = [:]
        for match in matches {
            rangesByTarget[match.target, default: []].append(match.range)
        }

        for (target, ranges) in rangesByTarget {
            let descending = ranges.sorted { $0.location > $1.location }
            apply(ranges: descending, replacement: replacementText, to: target, in: document)
        }

        search(in: document.blocks)
        return replacedCount
    }

    /// Rewrites `ranges` (which must be ordered last-to-first) within one target.
    @MainActor
    private func apply(
        ranges: [NSRange],
        replacement replacementText: String,
        to target: ReplaceTarget,
        in document: BlockEditorDocument
    ) {
        guard let original = currentText(of: target, in: document) else { return }

        let mutable = NSMutableString(string: original)
        for range in ranges {
            guard range.location >= 0, NSMaxRange(range) <= mutable.length else { continue }
            mutable.replaceCharacters(in: range, with: replacementText)
        }
        let updated = mutable as String
        guard updated != original else { return }

        if let itemID = target.itemID {
            document.updateListItemText(blockID: target.blockID, itemID: itemID, text: updated)
        } else {
            document.updateText(blockID: target.blockID, text: updated)
        }
    }

    @MainActor
    private func currentText(of target: ReplaceTarget, in document: BlockEditorDocument) -> String? {
        if let itemID = target.itemID {
            return document.listItemText(blockID: target.blockID, itemID: itemID)
        }
        return document.block(for: target.blockID)?.textContent
    }

    /// Search all blocks for occurrences of `query`.
    func search(in blocks: [Block]) {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        var results: [SearchMatch] = []
        var searchOptions: NSString.CompareOptions = [.diacriticInsensitive]
        if !matchCase {
            searchOptions.insert(.caseInsensitive)
        }

        for block in blocks {
            switch block {
            case let .paragraph(id, text),
                 let .heading(id, _, text),
                 let .blockQuote(id, text):
                results += findMatches(in: text, blockID: id, itemID: nil, options: searchOptions)

            case let .codeBlock(id, _, code):
                results += findMatches(in: code, blockID: id, itemID: nil, options: searchOptions)

            case let .bulletList(id, items), let .numberedList(id, items):
                for item in items {
                    results += findMatches(in: item.text, blockID: id, itemID: item.id, options: searchOptions)
                }

            case let .checkboxList(id, items):
                for item in items {
                    results += findMatches(in: item.text, blockID: id, itemID: item.id, options: searchOptions)
                }

            case let .mermaid(id, source):
                results += findMatches(in: source, blockID: id, itemID: nil, options: searchOptions)

            case let .math(id, latex):
                results += findMatches(in: latex, blockID: id, itemID: nil, options: searchOptions)

            case .table, .divider:
                break
            }
        }

        matches = results

        // Clamp current index
        if currentMatchIndex >= matches.count {
            currentMatchIndex = 0
        }
    }

    private func findMatches(
        in text: String,
        blockID: BlockID,
        itemID: UUID?,
        options: NSString.CompareOptions
    ) -> [SearchMatch] {
        guard !text.isEmpty else { return [] }
        let nsText = text as NSString
        var results: [SearchMatch] = []
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: query, options: options, range: searchRange)
            guard foundRange.location != NSNotFound else { break }

            if wholeWord {
                // Check that characters before and after the match are not word characters
                let isWordBoundaryBefore: Bool
                if foundRange.location > 0 {
                    let ch = text[text.index(text.startIndex, offsetBy: foundRange.location - 1)]
                    isWordBoundaryBefore = !ch.isLetter && !ch.isNumber && ch != "_"
                } else {
                    isWordBoundaryBefore = true
                }

                let isWordBoundaryAfter: Bool
                let afterIdx = foundRange.location + foundRange.length
                if afterIdx < text.count {
                    let ch = text[text.index(text.startIndex, offsetBy: afterIdx)]
                    isWordBoundaryAfter = !ch.isLetter && !ch.isNumber && ch != "_"
                } else {
                    isWordBoundaryAfter = true
                }

                if isWordBoundaryBefore, isWordBoundaryAfter {
                    results.append(SearchMatch(blockID: blockID, itemID: itemID, range: foundRange))
                }
            } else {
                results.append(SearchMatch(blockID: blockID, itemID: itemID, range: foundRange))
            }

            searchRange.location = NSMaxRange(foundRange)
            searchRange.length = nsText.length - searchRange.location
        }

        return results
    }
}
