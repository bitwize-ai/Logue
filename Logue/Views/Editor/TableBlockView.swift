import AppKit
import SwiftUI

// MARK: - TableBlockView

/// Interactive table view component that renders and edits a table block.
/// Added as a subview of the NSTextView and positioned over the attachment rect.
///
/// Drawing logic is in `TableBlockView+Drawing.swift`.
/// Context menu and spell popover are in `TableBlockView+ContextMenu.swift`.
final class TableBlockView: NSView {
    let tableData: TableBlockData
    var onDataChanged: (() -> Void)?
    /// Maximum width available for the table (set from the text container width).
    var availableWidth: CGFloat = 800

    var editingCell: (row: Int, col: Int)?
    var editField: NSTextField?
    var hoveredRow: Int = -1

    let cellPadding: CGFloat = TableBlockData.cellPadding
    let cornerRadius: CGFloat = 4
    let cellFont: NSFont = TableBlockData.cellFont

    /// Cached misspelled word hit targets for click-to-fix popover.
    struct SpellHit {
        let word: String
        let replacement: String
        let explanation: String
        let underlineRect: NSRect
        let row: Int
        let col: Int
        let range: NSRange
    }

    var spellHits: [SpellHit] = []

    /// Cached row heights, recomputed on layout changes.
    var cachedRowHeights: [CGFloat] = []

    /// Cumulative Y positions for each row (prefix sums), avoids O(n) per rowY call.
    private var cachedRowYPositions: [CGFloat] = []

    func recomputeRowHeights() {
        cachedRowHeights = tableData.rowHeights()
        cachedRowYPositions = cachedRowHeights.reduce(into: [0]) { result, height in
            result.append((result.last ?? 0) + height)
        }
    }

    func rowY(_ row: Int) -> CGFloat {
        row < cachedRowYPositions.count ? cachedRowYPositions[row] : 0
    }

    func rowHeight(_ row: Int) -> CGFloat {
        row < cachedRowHeights.count ? cachedRowHeights[row] : TableBlockData.minRowHeight
    }

    /// Whether adding more columns is possible (not all at minimum width).
    var canAddColumn: Bool {
        let maxTableWidth = availableWidth - TableBlockData.addColBtnWidth
        let newColCount = tableData.columns + 1
        return maxTableWidth >= CGFloat(newColCount) * TableBlockData.minColumnWidth
    }

    override var isFlipped: Bool {
        true
    }

    init(tableData: TableBlockData) {
        self.tableData = tableData
        super.init(frame: .zero)
        wantsLayer = true
        recomputeRowHeights()
        setupTracking()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not supported")
    }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    /// Updates the frame to match the table's current size.
    func updateSize() {
        recomputeRowHeights()
        setFrameSize(tableData.fullSize)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        recomputeRowHeights()
        spellHits.removeAll()

        let tableRect = NSRect(x: 0, y: 0, width: tableData.tableWidth, height: tableData.tableHeight)

        drawRowHoverHighlight(tableRect)
        drawGridLines(tableRect)
        drawCellText()
        drawAddRowButton(below: tableRect)
        drawAddColumnButton(rightOf: tableRect)
    }

    // MARK: - Cell Geometry

    func cellRect(row: Int, col: Int) -> NSRect {
        var x: CGFloat = 0
        for colIdx in 0 ..< col {
            x += tableData.columnWidths[colIdx]
        }
        let y = rowY(row)
        return NSRect(x: x, y: y, width: tableData.columnWidths[col], height: rowHeight(row))
    }

    /// Returns the row index at a given y coordinate, or -1 if outside.
    func rowIndex(atY y: CGFloat) -> Int {
        var cumY: CGFloat = 0
        for row in 0 ..< cachedRowHeights.count {
            cumY += cachedRowHeights[row]
            if y < cumY {
                return row
            }
        }
        return -1
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let newHovered = rowIndex(atY: loc.y)
        if newHovered != hoveredRow {
            hoveredRow = newHovered
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredRow != -1 {
            hoveredRow = -1
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Check add-row button
        let btnH = TableBlockData.addBtnHeight - 6
        let addRowRect = NSRect(
            x: tableData.tableWidth / 2 - 40, y: tableData.tableHeight + 3,
            width: 80, height: btnH
        )
        if addRowRect.contains(loc) {
            addRow()
            return
        }

        // Check add-column button
        let btnW = TableBlockData.addColBtnWidth - 6
        let addColRect = NSRect(
            x: tableData.tableWidth + 3, y: tableData.tableHeight / 2 - btnW / 2,
            width: btnW, height: btnW
        )
        if addColRect.contains(loc) {
            addColumn()
            return
        }

        // Check spell underline click — show suggestion popover
        if let hit = spellHits.first(where: { $0.underlineRect.contains(loc) }) {
            showSpellPopover(for: hit, at: hit.underlineRect)
            return
        }

        // Check cell click
        for row in 0 ..< tableData.rows.count {
            for col in 0 ..< tableData.columns {
                let rect = cellRect(row: row, col: col)
                if rect.contains(loc) {
                    startEditing(row: row, col: col)
                    return
                }
            }
        }

        // Click outside table cells — end editing
        commitEditing()
    }

    // MARK: - Cell Editing

    func startEditing(row: Int, col: Int) {
        commitEditing()

        editingCell = (row, col)
        let rect = cellRect(row: row, col: col).insetBy(dx: cellPadding - 2, dy: 4)
        let field = NSTextField(frame: rect)
        field.stringValue = tableData.rows[row][col]
        field.font = cellFont
        field.isBordered = false
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        editField = field
        needsDisplay = true
    }

    func commitEditing() {
        guard let cell = editingCell, let field = editField else { return }
        tableData.rows[cell.row][cell.col] = field.stringValue
        field.removeFromSuperview()
        editField = nil
        editingCell = nil
        autoSizeColumns()
        recomputeRowHeights()
        updateSize()
        needsDisplay = true
        onDataChanged?()
    }

    func autoSizeColumns() {
        tableData.autoSizeColumns(availableWidth: availableWidth)
    }

    // MARK: - Add Row / Column

    func addRow() {
        commitEditing()
        tableData.rows.append(Array(repeating: "", count: tableData.columns))
        notifyLayoutChanged()
    }

    func addColumn() {
        guard canAddColumn else { return }
        commitEditing()

        let maxTableWidth = availableWidth - TableBlockData.addColBtnWidth
        let currentWidth = tableData.tableWidth
        let newColWidth = TableBlockData.defaultColumnWidth

        tableData.columns += 1

        if currentWidth + newColWidth <= maxTableWidth {
            tableData.columnWidths.append(newColWidth)
        } else {
            let equalWidth = max(TableBlockData.minColumnWidth, maxTableWidth / CGFloat(tableData.columns))
            tableData.columnWidths = Array(repeating: equalWidth, count: tableData.columns)
        }

        for i in 0 ..< tableData.rows.count {
            tableData.rows[i].append("")
        }
        notifyLayoutChanged()
    }

    /// Refreshes size and notifies the text view to relayout the attachment.
    func notifyLayoutChanged() {
        updateSize()
        needsDisplay = true
        onDataChanged?()
    }

    // MARK: - Column Resizing

    private var resizingColumn: Int?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private let resizeHandleWidth: CGFloat = 6

    override func resetCursorRects() {
        super.resetCursorRects()
        let tH = cachedRowHeights.reduce(0, +)
        var x: CGFloat = 0
        for col in 0 ..< tableData.columns - 1 {
            x += tableData.columnWidths[col]
            let handleRect = NSRect(
                x: x - resizeHandleWidth / 2, y: 0,
                width: resizeHandleWidth, height: tH
            )
            addCursorRect(handleRect, cursor: .resizeLeftRight)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        if resizingColumn == nil {
            var x: CGFloat = 0
            for col in 0 ..< tableData.columns - 1 {
                x += tableData.columnWidths[col]
                if abs(loc.x - x) < resizeHandleWidth {
                    resizingColumn = col
                    resizeStartX = loc.x
                    resizeStartWidth = tableData.columnWidths[col]
                    break
                }
            }
        }

        if let col = resizingColumn {
            let delta = loc.x - resizeStartX
            let otherColumnsWidth = tableData.tableWidth - tableData.columnWidths[col]
            let maxForCol = availableWidth - TableBlockData.addColBtnWidth - otherColumnsWidth
            let newWidth = max(TableBlockData.minColumnWidth, min(resizeStartWidth + delta, maxForCol))
            tableData.columnWidths[col] = newWidth
            updateSize()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    override func mouseUp(with _: NSEvent) {
        if resizingColumn != nil {
            resizingColumn = nil
            onDataChanged?()
        }
    }
}

// MARK: - NSTextFieldDelegate

extension TableBlockView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_: Notification) {
        commitEditing()
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            let prev = editingCell
            commitEditing()
            if let current = prev, let next = nextCell(after: current) {
                startEditing(row: next.row, col: next.col)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            let prev = editingCell
            commitEditing()
            if let current = prev, let prior = previousCell(before: current) {
                startEditing(row: prior.row, col: prior.col)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let prev = editingCell
            commitEditing()
            if let current = prev {
                if current.row + 1 < tableData.rows.count {
                    startEditing(row: current.row + 1, col: current.col)
                } else {
                    addRow()
                    startEditing(row: tableData.rows.count - 1, col: current.col)
                }
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitEditing()
            if let parentTextView = superview as? NSTextView {
                window?.makeFirstResponder(parentTextView)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let prev = editingCell
            commitEditing()
            if let current = prev, current.row > 0 {
                startEditing(row: current.row - 1, col: current.col)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let prev = editingCell
            commitEditing()
            if let current = prev, current.row + 1 < tableData.rows.count {
                startEditing(row: current.row + 1, col: current.col)
            }
            return true
        }
        return false
    }

    private func nextCell(after current: (row: Int, col: Int)) -> (row: Int, col: Int)? {
        if current.col + 1 < tableData.columns {
            return (current.row, current.col + 1)
        } else if current.row + 1 < tableData.rows.count {
            return (current.row + 1, 0)
        }
        return nil
    }

    private func previousCell(before current: (row: Int, col: Int)) -> (row: Int, col: Int)? {
        if current.col > 0 {
            return (current.row, current.col - 1)
        } else if current.row > 0 {
            return (current.row - 1, tableData.columns - 1)
        }
        return nil
    }
}
