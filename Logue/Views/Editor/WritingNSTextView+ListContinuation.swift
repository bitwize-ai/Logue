import AppKit

// MARK: - List Auto-Continuation & Keyboard Handling

extension WritingNSTextView {
    /// Known continuable prefixes (ordered longest-first for greedy matching).
    private static let continuablePrefixes = [
        "- [x] ", "- [ ] ",
        "- ", "* ", "+ ",
        "> ",
    ]

    /// Regex to match numbered list prefix like `1. ` or `12) `.
    private static let numberedPrefixRegex = try? NSRegularExpression(pattern: #"^(\d+)([.)]\s+)"#)

    // MARK: - Tab / Shift+Tab (list indent/outdent)

    override func insertTab(_ sender: Any?) {
        let nsString = string as NSString
        let sel = selectedRange()
        guard nsString.length > 0 else {
            super.insertTab(sender)
            return
        }
        let lr = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = nsString.substring(with: lr)

        if isListLine(lineText) {
            // Indent: add 2 spaces at line start (markdown nesting convention)
            replaceRange(NSRange(location: lr.location, length: 0), with: "  ")
            setSelectedRange(NSRange(location: sel.location + 2, length: 0))
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        let nsString = string as NSString
        let sel = selectedRange()
        guard nsString.length > 0 else {
            super.insertBacktab(sender)
            return
        }
        let lr = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = nsString.substring(with: lr)

        // Only outdent if line starts with 2+ spaces followed by a list marker
        if lineText.hasPrefix("  "), isListLine(String(lineText.dropFirst(2))) {
            replaceRange(NSRange(location: lr.location, length: 2), with: "")
            setSelectedRange(NSRange(location: max(lr.location, sel.location - 2), length: 0))
            return
        }
        super.insertBacktab(sender)
    }

    /// Checks whether a line of text is a list item (bullet, checkbox, numbered, or block quote).
    private func isListLine(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            return true
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        if trimmed.hasPrefix("> ") {
            return true
        }
        let lineNS = trimmed as NSString
        if let match = Self.numberedPrefixRegex?.firstMatch(
            in: trimmed, range: NSRange(location: 0, length: lineNS.length)
        ), match.range.location == 0 {
            return true
        }
        return false
    }

    // MARK: - Backspace (delete entire prefix for rendered components)

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        // If text is selected, let normal delete handle it
        guard sel.length == 0 else {
            super.deleteBackward(sender)
            return
        }

        // Protect table attachment characters (U+FFFC) from deletion
        if sel.location > 0, isTableAttachment(at: sel.location - 1) {
            return
        }

        let nsString = string as NSString
        guard nsString.length > 0 else {
            super.deleteBackward(sender)
            return
        }

        let safeLoc = min(sel.location, nsString.length - 1)
        let lr = nsString.lineRange(for: NSRange(location: max(0, safeLoc), length: 0))
        let lineText = nsString.substring(with: lr)
        let cursorInLine = sel.location - lr.location

        // Detect markdown prefix on this line (including leading spaces)
        let prefixLen = markdownPrefixLength(of: lineText)

        // If the line has a prefix and cursor is at or within the prefix boundary,
        // first try to outdent (remove leading spaces), then remove the prefix.
        if prefixLen > 0, cursorInLine <= prefixLen {
            // If line has leading spaces (nested list), outdent first
            if lineText.hasPrefix("  ") {
                let outdentRange = NSRange(location: lr.location, length: 2)
                replaceRange(outdentRange, with: "")
                setSelectedRange(NSRange(location: max(lr.location, sel.location - 2), length: 0))
                return
            }
            // No indentation — remove entire prefix
            let prefixRange = NSRange(location: lr.location, length: prefixLen)
            replaceRange(prefixRange, with: "")
            setSelectedRange(NSRange(location: lr.location, length: 0))
            return
        }

        super.deleteBackward(sender)
    }

    /// Returns the length of any markdown prefix at the start of the given line text,
    /// including any leading whitespace (for nested lists).
    private func markdownPrefixLength(of lineText: String) -> Int {
        let leadingSpaces = lineText.prefix(while: { $0 == " " })
        let leadingCount = leadingSpaces.count
        let afterSpaces = String(lineText.dropFirst(leadingCount))

        // Checkbox (check before bullet since `- [ ] ` starts with `- `)
        if afterSpaces.hasPrefix("- [x] ") || afterSpaces.hasPrefix("- [ ] ") {
            return leadingCount + 6
        }
        // Bullet
        for prefix in ["- ", "* ", "+ "] where afterSpaces.hasPrefix(prefix) {
            return leadingCount + prefix.count
        }
        // Quote
        if afterSpaces.hasPrefix("> ") {
            return leadingCount + 2
        }
        // Headings (longest first)
        if afterSpaces.hasPrefix("### ") {
            return leadingCount + 4
        }
        if afterSpaces.hasPrefix("## ") {
            return leadingCount + 3
        }
        if afterSpaces.hasPrefix("# ") {
            return leadingCount + 2
        }
        // Numbered list
        let lineNS = afterSpaces as NSString
        if let match = Self.numberedPrefixRegex?.firstMatch(
            in: afterSpaces,
            range: NSRange(location: 0, length: lineNS.length)
        ) {
            return leadingCount + match.range.length
        }
        return 0
    }

    // MARK: - Enter (auto-continue lists)

    override func insertNewline(_ sender: Any?) {
        // Don't insert newlines into table attachment characters
        if isCursorAdjacentToTableAttachment {
            return
        }

        let nsString = string as NSString
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        // Extract leading whitespace (for nested lists)
        let leadingSpaces = String(trimmedLine.prefix(while: { $0 == " " }))
        let contentAfterSpaces = String(trimmedLine.dropFirst(leadingSpaces.count))

        // Try static continuable prefixes (check against content after leading spaces)
        if let prefix = Self.continuablePrefixes.first(where: { contentAfterSpaces.hasPrefix($0) }) {
            let content = String(contentAfterSpaces.dropFirst(prefix.count))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line with just prefix → remove prefix, end the list
                replaceRange(lineRange, with: "\n")
                setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
                return
            }
            // Continue with same prefix (for todo, always continue unchecked)
            let continuationPrefix: String = if prefix == "- [x] " {
                "- [ ] "
            } else {
                prefix
            }
            let insertion = "\n" + leadingSpaces + continuationPrefix
            let insertAt = NSRange(location: sel.location, length: 0)
            replaceRange(insertAt, with: insertion)
            setSelectedRange(NSRange(location: sel.location + insertion.utf16.count, length: 0))
            return
        }

        // Try numbered list prefix (check against content after leading spaces)
        let lineNS = contentAfterSpaces as NSString
        let matchRange = NSRange(location: 0, length: lineNS.length)
        if let match = Self.numberedPrefixRegex?.firstMatch(in: contentAfterSpaces, range: matchRange),
           match.numberOfRanges >= 3
        {
            let numberStr = lineNS.substring(with: match.range(at: 1))
            let separator = lineNS.substring(with: match.range(at: 2))
            let prefixLen = match.range.length
            let content = String(contentAfterSpaces.dropFirst(prefixLen))

            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty numbered line → remove prefix
                replaceRange(lineRange, with: "\n")
                setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
                return
            }

            // Increment number
            let nextNumber = (Int(numberStr) ?? 0) + 1
            let nextPrefix = "\(nextNumber)\(separator)"
            let insertion = "\n" + leadingSpaces + nextPrefix
            let insertAt = NSRange(location: sel.location, length: 0)
            replaceRange(insertAt, with: insertion)
            setSelectedRange(NSRange(location: sel.location + insertion.utf16.count, length: 0))
            return
        }

        // Default: regular newline
        super.insertNewline(sender)
    }
}
