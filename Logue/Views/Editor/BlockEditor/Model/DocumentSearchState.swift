import Foundation

// MARK: - Search Match

struct SearchMatch: Identifiable {
    let id = UUID()
    let blockID: BlockID
    /// Non-nil for list/checkbox items to identify which item within the block.
    let itemID: UUID?
    /// Character range within the block's or item's text.
    let range: NSRange
}

// MARK: - Document Search State

@Observable
final class DocumentSearchState {
    var isActive = false
    var query = ""
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
        matches = []
        currentMatchIndex = 0
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
