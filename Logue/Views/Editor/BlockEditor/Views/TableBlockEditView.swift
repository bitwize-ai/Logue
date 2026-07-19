import SwiftUI

/// Pure SwiftUI editable table matching Textual's GitHub table style.
/// Features: 1px grid dividers, semibold header, alternating row tints,
/// font-scaled padding, inline TextField editing, horizontal scroll for wide tables.
struct TableBlockEditView: View {
    let blockID: BlockID
    let data: TableBlockData
    let document: BlockEditorDocument
    var fontSize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize
    var isFocused: Bool = false
    var onFocusGained: (() -> Void)?
    var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?

    @State private var editingCell: CellID?
    @State private var editText: String = ""

    private struct CellID: Equatable {
        let row: Int
        let col: Int
    }

    // Textual-matching constants — padding scales with fontSize
    private static let borderWidth: CGFloat = 1
    private var cellPaddingH: CGFloat {
        fontSize * 0.93
    }

    private var cellPaddingV: CGFloat {
        fontSize * 0.43
    }

    private static let borderColor = AppThemeConstants.tableBorderColor
    private static let headerBackground = AppThemeConstants.tableHeaderFill
    private var cellFont: Font {
        .system(size: fontSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal scroll for wide tables (Textual Overflow style)
            ScrollView(.horizontal, showsIndicators: true) {
                tableGrid
            }
            if isFocused {
                addRowButton
            }
        }
        .onTapGesture { onFocusGained?() }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitEditing()
            }
        }
        .contextMenu { tableContextMenu }
    }

    // MARK: - Table Grid

    private var tableGrid: some View {
        HStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: Self.borderWidth, verticalSpacing: Self.borderWidth) {
                ForEach(0 ..< data.rows.count, id: \.self) { rowIdx in
                    GridRow {
                        ForEach(0 ..< data.columns, id: \.self) { colIdx in
                            cellView(row: rowIdx, col: colIdx)
                                .background(rowBackground(rowIdx))
                        }
                    }
                }
            }
            .background(Self.borderColor) // Grid gaps become visible as 1px divider lines
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Self.borderColor, lineWidth: Self.borderWidth)
            )

            if isFocused {
                addColumnButton
            }
        }
    }

    /// Header row gets a subtle themed fill; body rows use the editor background so the
    /// border grid color underneath doesn't bleed through.
    private func rowBackground(_ rowIdx: Int) -> Color {
        rowIdx == 0 ? Self.headerBackground : AppThemeConstants.contentBackground
    }

    // MARK: - Cell View

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let isEditing = editingCell == CellID(row: row, col: col)
        let cellText = row < data.rows.count && col < data.rows[row].count ? data.rows[row][col] : ""

        Group {
            if isEditing {
                TableCellTextView(
                    text: $editText,
                    font: NSFont.systemFont(ofSize: fontSize),
                    isHeader: row == 0,
                    isFocused: true,
                    onTab: { commitAndMoveNext() },
                    onSubmit: { commitAndMoveDown() },
                    onEscape: { commitEditing() },
                    onSelectionChange: onSelectionChange
                )
            } else {
                Group {
                    if cellText.isEmpty {
                        Text(" ")
                            .foregroundStyle(.clear)
                    } else {
                        Text(Self.renderMarkdown(cellText, isHeader: row == 0))
                    }
                }
                .font(cellFont)
                .foregroundStyle(cellText.isEmpty ? .clear : .primary)
                .lineSpacing(3.5) // Textual: fontScaled(0.25) ~ 3.5pt at 14pt
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onFocusGained?()
                    if isFocused {
                        startEditing(row: row, col: col)
                    }
                }
            }
        }
        .padding(.horizontal, cellPaddingH)
        .padding(.vertical, cellPaddingV)
        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Row \(row + 1), column \(col + 1)")
        .accessibilityHint(isEditing ? "Editing" : "Double tap to edit")
    }

    // MARK: - Add Row Button

    private var addRowButton: some View {
        Button {
            addRow()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption2)
                Text("Row")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .help("Add row")
    }

    // MARK: - Add Column Button

    private var addColumnButton: some View {
        Button {
            addColumn()
        } label: {
            Image(systemName: "plus")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .help("Add column")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var tableContextMenu: some View {
        Button("Add Row") { addRow() }
        Button("Add Column") { addColumn() }

        if data.rows.count > 1 {
            Divider()
            Button("Delete Last Row", role: .destructive) { deleteLastRow() }
        }
        if data.columns > 1 {
            Button("Delete Last Column", role: .destructive) { deleteLastColumn() }
        }
    }

    // MARK: - Editing

    private func startEditing(row: Int, col: Int) {
        commitEditing()
        let cellText = row < data.rows.count && col < data.rows[row].count ? data.rows[row][col] : ""
        editText = cellText
        editingCell = CellID(row: row, col: col)
    }

    private func commitEditing() {
        guard let cell = editingCell else { return }
        if cell.row < data.rows.count, cell.col < data.rows[cell.row].count {
            data.rows[cell.row][cell.col] = editText
            document.updateTableData(blockID: blockID)
        }
        editingCell = nil
        editText = ""
    }

    private func commitAndMoveNext() {
        guard let cell = editingCell else { return }
        commitEditing()
        let nextCol = cell.col + 1
        if nextCol < data.columns {
            startEditing(row: cell.row, col: nextCol)
        } else if cell.row + 1 < data.rows.count {
            startEditing(row: cell.row + 1, col: 0)
        }
    }

    private func commitAndMoveDown() {
        guard let cell = editingCell else { return }
        commitEditing()
        if cell.row + 1 < data.rows.count {
            startEditing(row: cell.row + 1, col: cell.col)
        }
    }

    // MARK: - Table Mutations

    private func addRow() {
        commitEditing()
        data.rows.append(Array(repeating: "", count: data.columns))
        document.updateTableData(blockID: blockID)
    }

    private func addColumn() {
        commitEditing()
        data.columns += 1
        for i in 0 ..< data.rows.count {
            data.rows[i].append("")
        }
        data.columnWidths.append(TableBlockData.defaultColumnWidth)
        document.updateTableData(blockID: blockID)
    }

    private func deleteLastRow() {
        guard data.rows.count > 1 else { return }
        commitEditing()
        data.rows.removeLast()
        document.updateTableData(blockID: blockID)
    }

    private func deleteLastColumn() {
        guard data.columns > 1 else { return }
        commitEditing()
        data.columns -= 1
        for i in 0 ..< data.rows.count where !data.rows[i].isEmpty {
            data.rows[i].removeLast()
        }
        if data.columnWidths.count > data.columns {
            data.columnWidths.removeLast()
        }
        document.updateTableData(blockID: blockID)
    }

    // MARK: - Markdown Rendering

    /// Renders cell text as markdown AttributedString, with a fallback that strips delimiters.
    static func renderMarkdown(_ text: String, isHeader: Bool = false) -> AttributedString {
        // Try standard markdown parsing first
        var attrStr: AttributedString
        if let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            attrStr = parsed
        } else {
            // Fallback: strip common delimiters for display
            var stripped = text
            stripped = stripped.replacingOccurrences(of: "**", with: "")
            stripped = stripped.replacingOccurrences(of: "~~", with: "")
            attrStr = AttributedString(stripped)
        }
        // Apply header weight directly in the AttributedString
        if isHeader {
            attrStr.font = .system(size: 14, weight: .semibold)
        }
        return attrStr
    }
}
