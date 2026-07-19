import AppKit

// MARK: - Drawing

extension TableBlockView {
    func drawRowHoverHighlight(_ tableRect: NSRect) {
        guard hoveredRow >= 0, hoveredRow < tableData.rows.count else { return }
        let y = rowY(hoveredRow)
        let height = rowHeight(hoveredRow)
        let highlightRect = NSRect(x: 0, y: y, width: tableRect.width, height: height)
        NSColor.labelColor.withAlphaComponent(0.03).setFill()
        highlightRect.fill()
    }

    func drawGridLines(_ tableRect: NSRect) {
        let borderColor = NSColor.separatorColor

        // Outer border
        borderColor.setStroke()
        let outerPath = NSBezierPath(roundedRect: tableRect, xRadius: cornerRadius, yRadius: cornerRadius)
        outerPath.lineWidth = 0.5
        outerPath.stroke()

        // Horizontal row lines
        for row in 1 ..< tableData.rows.count {
            let y = rowY(row)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: tableRect.width, y: y))
            line.lineWidth = 0.5
            borderColor.setStroke()
            line.stroke()
        }

        // Vertical column lines
        var x: CGFloat = 0
        for col in 0 ..< tableData.columns - 1 {
            x += tableData.columnWidths[col]
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 0))
            line.line(to: NSPoint(x: x, y: tableRect.height))
            line.lineWidth = 0.5
            borderColor.setStroke()
            line.stroke()
        }
    }

    func drawCellText() {
        let checker = NSSpellChecker.shared
        for (rowIdx, row) in tableData.rows.enumerated() {
            for (colIdx, text) in row.enumerated() {
                if editingCell?.row == rowIdx, editingCell?.col == colIdx {
                    continue
                }

                let rect = cellRect(row: rowIdx, col: colIdx)
                let color: NSColor = text.isEmpty ? .tertiaryLabelColor : .labelColor

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .foregroundColor: color,
                ]
                let attrStr = NSAttributedString(string: text, attributes: attrs)
                let textW = rect.width - cellPadding * 2
                let textH = rect.height - 8
                let textRect = NSRect(
                    x: rect.minX + cellPadding,
                    y: rect.minY + 4,
                    width: textW,
                    height: textH
                )
                attrStr.draw(with: textRect, options: [.usesLineFragmentOrigin])

                if !text.isEmpty {
                    drawSpellUnderlines(
                        for: text, in: textRect, row: rowIdx, col: colIdx,
                        checker: checker, attrs: attrs
                    )
                }
            }
        }
    }

    /// Computes the x offset and y position for a word at a given location in wrapped text.
    func wordPosition(
        beforeText: String, textRect: NSRect, lineHeight: CGFloat,
        attrs: [NSAttributedString.Key: Any]
    ) -> (xOffset: CGFloat, lineY: CGFloat) {
        let beforeSize = (beforeText as NSString).size(withAttributes: attrs)
        let beforeRect = (beforeText as NSString).boundingRect(
            with: NSSize(width: textRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let lineIndex = beforeSize.width > textRect.width
            ? Int(beforeRect.height / lineHeight) - 1
            : 0
        let lineY = textRect.minY + CGFloat(lineIndex) * lineHeight + lineHeight - 1
        let xOffset: CGFloat = if beforeSize.width <= textRect.width {
            textRect.minX + beforeSize.width
        } else {
            textRect.minX + beforeSize.width.truncatingRemainder(dividingBy: textRect.width)
        }
        return (xOffset, lineY)
    }

    /// Draws solid red underlines under misspelled words and caches hit rects for click-to-fix popover.
    func drawSpellUnderlines(
        for text: String,
        in textRect: NSRect,
        row: Int, col: Int,
        checker: NSSpellChecker,
        attrs: [NSAttributedString.Key: Any]
    ) {
        let nsText = text as NSString
        var offset = 0
        let lineHeight = ceil(cellFont.ascender - cellFont.descender + cellFont.leading)

        while offset < nsText.length {
            let misspelled = checker.checkSpelling(
                of: text, startingAt: offset, language: nil,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
            )
            guard misspelled.location != NSNotFound else { break }

            let beforeText = nsText.substring(to: misspelled.location)
            let wordText = nsText.substring(with: misspelled)
            let wordSize = (wordText as NSString).size(withAttributes: attrs)
            let pos = wordPosition(beforeText: beforeText, textRect: textRect, lineHeight: lineHeight, attrs: attrs)
            let underlineWidth = min(wordSize.width, textRect.maxX - pos.xOffset)

            NSColor.systemRed.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: pos.xOffset, y: pos.lineY))
            path.line(to: NSPoint(x: pos.xOffset + underlineWidth, y: pos.lineY))
            path.lineWidth = 1.0
            path.stroke()

            let guesses = checker.guesses(
                forWordRange: misspelled, in: text,
                language: nil, inSpellDocumentWithTag: 0
            ) ?? []
            let best = guesses.first ?? wordText
            spellHits.append(SpellHit(
                word: wordText, replacement: best,
                explanation: guesses.isEmpty ? "Possible spelling error." : "Did you mean \"\(best)\"?",
                underlineRect: NSRect(x: pos.xOffset, y: pos.lineY - lineHeight, width: underlineWidth, height: lineHeight + 2),
                row: row, col: col, range: misspelled
            ))

            offset = NSMaxRange(misspelled)
        }
    }

    func drawAddRowButton(below tableRect: NSRect) {
        let btnH = TableBlockData.addBtnHeight - 6
        let btnRect = NSRect(
            x: tableRect.width / 2 - 40,
            y: tableRect.height + 3,
            width: 80,
            height: btnH
        )
        NSColor.tertiaryLabelColor.withAlphaComponent(0.3).setStroke()
        let path = NSBezierPath(roundedRect: btnRect, xRadius: 4, yRadius: 4)
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let str = NSAttributedString(string: "+ Row", attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: btnRect.midX - strSize.width / 2, y: btnRect.midY - strSize.height / 2))
    }

    func drawAddColumnButton(rightOf tableRect: NSRect) {
        guard canAddColumn else { return }
        let btnW = TableBlockData.addColBtnWidth - 6
        let btnRect = NSRect(
            x: tableRect.width + 3,
            y: tableRect.height / 2 - btnW / 2,
            width: btnW,
            height: btnW
        )
        NSColor.tertiaryLabelColor.withAlphaComponent(0.3).setStroke()
        let path = NSBezierPath(roundedRect: btnRect, xRadius: 4, yRadius: 4)
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .light),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let str = NSAttributedString(string: "+", attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: btnRect.midX - strSize.width / 2, y: btnRect.midY - strSize.height / 2))
    }
}
