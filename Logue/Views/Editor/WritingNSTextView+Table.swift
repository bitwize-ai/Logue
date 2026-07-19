import AppKit

// MARK: - Table Attachment Helpers

extension WritingNSTextView {
    /// Returns true if the cursor is adjacent to a table attachment (U+FFFC).
    /// Used to guard against accidentally deleting the attachment character.
    var isCursorAdjacentToTableAttachment: Bool {
        guard let textStorage, textStorage.length > 0 else { return false }
        let loc = selectedRange().location
        // Check character before cursor
        if loc > 0 {
            if textStorage.attribute(.attachment, at: loc - 1, effectiveRange: nil) is TableAttachment {
                return true
            }
        }
        // Check character at cursor
        if loc < textStorage.length {
            if textStorage.attribute(.attachment, at: loc, effectiveRange: nil) is TableAttachment {
                return true
            }
        }
        return false
    }

    /// Returns true if the character at the given index is a table attachment.
    func isTableAttachment(at charIndex: Int) -> Bool {
        guard let textStorage, charIndex >= 0, charIndex < textStorage.length else { return false }
        return textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) is TableAttachment
    }
}
