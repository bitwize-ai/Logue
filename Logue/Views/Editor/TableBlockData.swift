import AppKit

// MARK: - Table Data Model

/// Stores table cell data for an embedded table block.
final class TableBlockData {
    var columns: Int
    var rows: [[String]] // rows[0] = first row (no special header treatment)
    var columnWidths: [CGFloat]
    /// Incremented on every mutation to ensure Equatable detects changes.
    var version: Int = 0

    init(columns: Int = 3, rowCount: Int = 2, availableWidth: CGFloat? = nil) {
        self.columns = columns
        rows = (0 ..< rowCount).map { _ in
            Array(repeating: "", count: columns)
        }
        if let available = availableWidth {
            // Fill available width with equal columns (Notion-style)
            let tableArea = available - Self.addColBtnWidth
            let colWidth = max(Self.minColumnWidth, tableArea / CGFloat(columns))
            columnWidths = Array(repeating: colWidth, count: columns)
        } else {
            columnWidths = Array(repeating: Self.defaultColumnWidth, count: columns)
        }
    }

    static let minRowHeight: CGFloat = 36
    static let addBtnHeight: CGFloat = 26
    static let addColBtnWidth: CGFloat = 26
    static let minColumnWidth: CGFloat = 60
    static let defaultColumnWidth: CGFloat = 150

    /// Font used for measuring cell text height.
    static let cellFont: NSFont = .systemFont(ofSize: 14)
    static let cellPadding: CGFloat = 10

    var tableWidth: CGFloat {
        columnWidths.reduce(0, +)
    }

    /// Auto-expands column widths to fit content, up to the max available width.
    func autoSizeColumns(availableWidth: CGFloat) {
        let maxTableWidth = availableWidth - Self.addColBtnWidth
        let maxPerColumn = maxTableWidth / CGFloat(columns)

        for col in 0 ..< columns {
            var neededWidth = Self.minColumnWidth
            for row in rows {
                let text = col < row.count ? row[col] : ""
                guard !text.isEmpty else { continue }
                let attrs: [NSAttributedString.Key: Any] = [.font: Self.cellFont]
                let size = (text as NSString).size(withAttributes: attrs)
                let cellNeeded = ceil(size.width) + Self.cellPadding * 2 + 4
                neededWidth = max(neededWidth, cellNeeded)
            }
            columnWidths[col] = min(neededWidth, maxPerColumn)
        }
    }

    /// Computes the height of each row based on the tallest cell's wrapped text.
    func rowHeights() -> [CGFloat] {
        rows.map { row in
            var maxH = Self.minRowHeight
            for (colIdx, text) in row.enumerated() {
                guard !text.isEmpty else { continue }
                let colW = colIdx < columnWidths.count ? columnWidths[colIdx] : Self.defaultColumnWidth
                let textW = colW - Self.cellPadding * 2
                let attrs: [NSAttributedString.Key: Any] = [.font: Self.cellFont]
                let boundingRect = (text as NSString).boundingRect(
                    with: NSSize(width: textW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs
                )
                let needed = ceil(boundingRect.height) + 12 // vertical padding
                maxH = max(maxH, needed)
            }
            return maxH
        }
    }

    var tableHeight: CGFloat {
        rowHeights().reduce(0, +)
    }

    /// Full size including add-row button below and add-column button right.
    var fullSize: NSSize {
        NSSize(
            width: tableWidth + Self.addColBtnWidth,
            height: tableHeight + Self.addBtnHeight
        )
    }

    /// Convert table data to markdown text for serialization.
    func toMarkdown() -> String {
        guard !rows.isEmpty else { return "" }
        var lines: [String] = []
        for (rowIdx, row) in rows.enumerated() {
            let cells = row.map { " \($0) " }
            lines.append("|\(cells.joined(separator: "|"))|")
            if rowIdx == 0 {
                let seps = row.map { _ in " --- " }
                lines.append("|\(seps.joined(separator: "|"))|")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Table Attachment

/// NSTextAttachment that holds table block data and embeds the table UI in the text.
final class TableAttachment: NSTextAttachment {
    let tableID = UUID()
    let tableData: TableBlockData

    init(tableData: TableBlockData) {
        self.tableData = tableData
        super.init(data: nil, ofType: nil)
        attachmentCell = TableAttachmentCell()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not supported")
    }
}

// MARK: - Table Attachment Cell

/// Controls the layout size of the table attachment in the text flow.
/// The size must match the overlay TableBlockView exactly so text reflows correctly.
final class TableAttachmentCell: NSTextAttachmentCell {
    override func cellFrame(
        for _: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition _: NSPoint,
        characterIndex _: Int
    ) -> NSRect {
        guard let tableAttachment = attachment as? TableAttachment else {
            return NSRect(x: 0, y: 0, width: lineFrag.width, height: 80)
        }
        let size = tableAttachment.tableData.fullSize
        let width = min(size.width, lineFrag.width)
        return NSRect(x: 0, y: -2, width: width, height: size.height)
    }

    override func cellBaselineOffset() -> NSPoint {
        guard let tableAttachment = attachment as? TableAttachment else {
            return NSPoint(x: 0, y: -2)
        }
        return NSPoint(x: 0, y: -tableAttachment.tableData.fullSize.height + 14)
    }

    override func draw(withFrame _: NSRect, in _: NSView?) {
        // Intentionally empty — TableBlockView overlay handles rendering.
    }

    override func draw(withFrame _: NSRect, in _: NSView?, characterIndex _: Int, layoutManager _: NSLayoutManager) {
        // Intentionally empty — TableBlockView overlay handles rendering.
    }
}
