import AppKit
import SwiftUI

// MARK: - Context Menu & Spell Popover

extension TableBlockView {
    func showSpellPopover(for hit: SpellHit, at rect: NSRect) {
        let suggestion = Suggestion(
            id: UUID(),
            type: .spelling,
            original: hit.word,
            replacement: hit.replacement,
            explanation: hit.explanation,
            confidence: 0.90,
            textRange: hit.range
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let popoverView = InlineSuggestionPopoverView(
            suggestion: suggestion,
            onAccept: { [weak self, weak popover] in
                guard let self,
                      hit.row < tableData.rows.count,
                      hit.col < tableData.rows[hit.row].count
                else { return }
                let nsCell = tableData.rows[hit.row][hit.col] as NSString
                let newText = nsCell.replacingCharacters(in: hit.range, with: hit.replacement)
                tableData.rows[hit.row][hit.col] = newText
                autoSizeColumns()
                recomputeRowHeights()
                updateSize()
                needsDisplay = true
                onDataChanged?()
                popover?.close()
            },
            onDismiss: { [weak popover] in
                popover?.close()
            }
        )
        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.show(relativeTo: rect, of: self, preferredEdge: .minY)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let row = rowIndex(atY: loc.y)
        let menu = NSMenu()

        let addRowItem = NSMenuItem(title: "Add Row Below", action: #selector(contextAddRow), keyEquivalent: "")
        addRowItem.target = self
        addRowItem.image = NSImage(systemSymbolName: "plus.rectangle", accessibilityDescription: nil)
        menu.addItem(addRowItem)

        if tableData.rows.count > 1, row >= 0, row < tableData.rows.count {
            let delRowItem = NSMenuItem(title: "Delete Row", action: #selector(contextDeleteRow), keyEquivalent: "")
            delRowItem.target = self
            delRowItem.tag = row
            delRowItem.image = NSImage(systemSymbolName: "minus.rectangle", accessibilityDescription: nil)
            menu.addItem(delRowItem)
        }

        menu.addItem(.separator())

        let addColItem = NSMenuItem(title: "Add Column", action: #selector(contextAddColumn), keyEquivalent: "")
        addColItem.target = self
        addColItem.image = NSImage(systemSymbolName: "plus.rectangle.portrait", accessibilityDescription: nil)
        menu.addItem(addColItem)

        if tableData.columns > 1 {
            var xPos: CGFloat = 0
            var clickedCol = 0
            for col in 0 ..< tableData.columns {
                if loc.x < xPos + tableData.columnWidths[col] {
                    clickedCol = col
                    break
                }
                xPos += tableData.columnWidths[col]
                if col == tableData.columns - 1 {
                    clickedCol = col
                }
            }

            let delColItem = NSMenuItem(title: "Delete Column", action: #selector(contextDeleteColumn), keyEquivalent: "")
            delColItem.target = self
            delColItem.tag = clickedCol
            delColItem.image = NSImage(systemSymbolName: "minus.rectangle.portrait", accessibilityDescription: nil)
            menu.addItem(delColItem)
        }

        return menu
    }

    @objc
    func contextAddRow() {
        addRow()
    }

    @objc
    func contextDeleteRow(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < tableData.rows.count, tableData.rows.count > 1 else { return }
        commitEditing()
        tableData.rows.remove(at: row)
        notifyLayoutChanged()
    }

    @objc
    func contextAddColumn() {
        addColumn()
    }

    @objc
    func contextDeleteColumn(_ sender: NSMenuItem) {
        let col = sender.tag
        guard col >= 0, col < tableData.columns, tableData.columns > 1 else { return }
        commitEditing()
        tableData.columns -= 1
        tableData.columnWidths.remove(at: col)
        for idx in 0 ..< tableData.rows.count {
            tableData.rows[idx].remove(at: col)
        }
        notifyLayoutChanged()
    }
}
