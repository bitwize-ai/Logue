import AppKit
import SwiftUI

// MARK: - Slash Command

extension WritingNSTextView {
    /// Called from textDidChange to check if slash command should show/hide/update.
    func updateSlashCommandState() {
        let sel = selectedRange()
        guard sel.length == 0 else {
            hideSlashCommandPanel()
            return
        }

        let nsString = string as NSString
        guard nsString.length > 0 else {
            hideSlashCommandPanel()
            return
        }

        let loc = sel.location
        let lineRange = nsString.lineRange(for: NSRange(location: min(loc, nsString.length - 1), length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        // Check if line starts with `/`
        guard trimmedLine.hasPrefix("/") else {
            hideSlashCommandPanel()
            return
        }

        let query = String(trimmedLine.dropFirst())
        slashTriggerIndex = lineRange.location

        showSlashCommandPanel(query: query, triggerLineRange: lineRange)
    }

    private func showSlashCommandPanel(query: String, triggerLineRange: NSRange) {
        guard let layoutManager,
              let window
        else { return }

        // Get position of the `/` character
        let glyphIdx = layoutManager.glyphIndexForCharacter(at: triggerLineRange.location)
        guard glyphIdx < layoutManager.numberOfGlyphs else { return }

        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
        lineRect.origin.x += textContainerOrigin.x
        lineRect.origin.y += textContainerOrigin.y

        // Position below the line
        let posInView = NSPoint(x: lineRect.origin.x, y: lineRect.maxY)
        let windowPt = convert(posInView, to: nil)
        let screenPt = window.convertToScreen(NSRect(origin: windowPt, size: .zero)).origin

        // Create or update panel content
        let slashView = SlashCommandView(
            filterText: query,
            onSelect: { [weak self] blockType in
                self?.applySlashCommand(blockType)
            },
            onDismiss: { [weak self] in
                self?.hideSlashCommandPanel()
            }
        )

        if slashCommandPanel == nil {
            let hostingView = NSHostingView(rootView: slashView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 320),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: true
            )
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.contentView = hostingView
            slashCommandPanel = panel
        } else if let hostingView = slashCommandPanel?.contentView as? NSHostingView<SlashCommandView> {
            hostingView.rootView = slashView
        }

        guard let panel = slashCommandPanel else { return }

        let pWidth: CGFloat = 240
        let pHeight: CGFloat = 320
        let x = screenPt.x
        let y = screenPt.y - pHeight // Below the text (screen y goes up)

        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.setFrame(NSRect(x: x, y: y, width: pWidth, height: pHeight), display: true)
        panel.orderFront(nil)
    }

    func hideSlashCommandPanel() {
        if let panel = slashCommandPanel, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        slashCommandPanel?.orderOut(nil)
        slashTriggerIndex = nil
    }

    private func applySlashCommand(_ blockType: BlockType) {
        guard let triggerIdx = slashTriggerIndex else { return }
        hideSlashCommandPanel()

        // Remove the `/query` text on the current line
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: triggerIdx, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let hasNewline = lineText.hasSuffix("\n")

        switch blockType {
        case .divider:
            let replacement = "---" + (hasNewline ? "\n" : "")
            replaceRange(lineRange, with: replacement)
            setSelectedRange(NSRange(location: lineRange.location + replacement.utf16.count, length: 0))

        case .codeBlock:
            let replacement = "```\n\n```" + (hasNewline ? "\n" : "")
            replaceRange(lineRange, with: replacement)
            // Cursor inside code block
            setSelectedRange(NSRange(location: lineRange.location + 4, length: 0))

        case .table:
            // Remove the /query line first, then insert table block
            replaceRange(lineRange, with: hasNewline ? "\n" : "")
            insertTableBlock(at: lineRange.location)

        default:
            let prefix = blockType.markdownPrefix
            let replacement = prefix + (hasNewline ? "\n" : "")
            replaceRange(lineRange, with: replacement)
            setSelectedRange(NSRange(location: lineRange.location + prefix.utf16.count, length: 0))
        }
    }
}
