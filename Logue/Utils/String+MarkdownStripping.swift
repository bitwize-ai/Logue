import Foundation

extension String {
    /// Strips inline markdown delimiters (`**`, `*`, `__`, `_`, `~~`, `` ` ``) for plain-text matching.
    /// Uses a single regex pass instead of 6 sequential string scans.
    var strippingInlineMarkdown: String {
        replacingOccurrences(of: "\\*\\*|__|~~|[*_`]", with: "", options: .regularExpression)
    }

    /// Builds a mapping from each character index in the stripped string back to its index in `self`.
    /// Used to convert a range found in the stripped string into the corresponding range in the original.
    func markdownStrippedIndexMap() -> (stripped: String, map: [Int]) {
        var stripped = ""
        var map: [Int] = []
        let chars = Array(self)
        var idx = 0
        // Multi-char delimiters to skip (order: longest first)
        let delimiters = ["**", "__", "~~"]
        let singleDelimiters: Set<Character> = ["*", "_", "`"]

        while idx < chars.count {
            var skipped = false
            for delim in delimiters {
                let end = idx + delim.count
                if end <= chars.count, String(chars[idx ..< end]) == delim {
                    idx += delim.count
                    skipped = true
                    break
                }
            }
            if skipped {
                continue
            }
            if singleDelimiters.contains(chars[idx]) {
                idx += 1
                continue
            }
            map.append(idx)
            stripped.append(chars[idx])
            idx += 1
        }
        return (stripped, map)
    }
}
