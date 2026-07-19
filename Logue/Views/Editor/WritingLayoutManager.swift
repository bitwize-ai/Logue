import AppKit
import SwiftUI

// MARK: - Custom Attribute Key

extension NSAttributedString.Key {
    /// Marker type for visual list rendering.
    /// Values: "bullet", "numberedList:<n>", "checkboxUnchecked", "checkboxChecked", "tablePipe", "tableSeparator"
    static let listMarkerType = NSAttributedString.Key("com.logue.listMarkerType")
    /// Boolean flag on table header rows for background rendering.
    static let tableHeaderRow = NSAttributedString.Key("com.logue.tableHeaderRow")
    /// Column count (Int) applied to the entire table range for grid rendering.
    static let tableColumnCount = NSAttributedString.Key("com.logue.tableColumnCount")
    /// Boolean flag marking block quote ranges for left-border rendering.
    static let blockQuoteRange = NSAttributedString.Key("com.logue.blockQuoteRange")
    /// Boolean flag marking code block ranges for container background rendering.
    static let codeBlockRange = NSAttributedString.Key("com.logue.codeBlockRange")
    /// String value: the language label for a code block (e.g., "swift").
    static let codeBlockLanguage = NSAttributedString.Key("com.logue.codeBlockLanguage")
    /// Boolean flag marking thematic break (divider) ranges for horizontal line rendering.
    static let dividerRange = NSAttributedString.Key("com.logue.dividerRange")
    /// Int value: nesting depth for list items (1 = top-level, 2 = first nested, etc.).
    static let listNestingDepth = NSAttributedString.Key("com.logue.listNestingDepth")
}

// MARK: - WritingLayoutManager

/// Custom layout manager that draws visual replacements for hidden list markers.
/// Bullet markers (`- `, `* `, `+ `) → filled circle.
/// Checkbox markers (`- [ ] `, `- [x] `) → checkbox visual.
final class WritingLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawCodeBlockBackgrounds(forCharRange: charRange, at: origin)
        drawTableBackgrounds(forCharRange: charRange, at: origin)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawBlockQuoteBorders(forCharRange: charRange, at: origin)
        drawDividers(forCharRange: charRange, at: origin)
        drawCodeBlockBorders(forCharRange: charRange, at: origin)
        drawTableBorders(forCharRange: charRange, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawListMarkers(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let bgColor = textContainers.first?.textView?.backgroundColor ?? .textBackgroundColor

        textStorage.enumerateAttribute(.listMarkerType, in: charRange) { value, range, _ in
            guard let type = value as? String else { return }
            let gr = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard gr.location != NSNotFound, gr.length > 0 else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
            let loc = self.location(forGlyphAt: gr.location)
            // Use lineFragmentUsedRect for the actual text height (excludes paragraph spacing)
            let usedRect = self.lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)

            let x = origin.x + lineRect.origin.x + loc.x
            // Position markers at the bottom of the line fragment (where text actually sits)
            // by offsetting by the difference between full rect and used rect
            let spacingOffset = lineRect.height - usedRect.height
            let y = origin.y + lineRect.origin.y + spacingOffset
            let lineHeight = usedRect.height

            // Paint over the marker area to erase any foreground color that would reveal
            // hidden syntax. Use the selection highlight color if the marker is selected,
            // otherwise use the background color.
            // Skip for headings (zero-width) and table markers (handled by drawTableBorders).
            let skipClear = type == "heading" || type == "tableSeparator" || type == "tablePipe" || type == "divider"
            if !skipClear, let tc = self.textContainers.first {
                let markerBounds = self.boundingRect(forGlyphRange: gr, in: tc)
                let clearRect = NSRect(
                    x: origin.x + markerBounds.origin.x,
                    y: y,
                    width: markerBounds.width + 1,
                    height: lineHeight
                )
                let isSelected = tc.textView?.selectedRanges.contains(where: {
                    NSIntersectionRange($0.rangeValue, range).length > 0
                }) ?? false
                let fillColor = isSelected ? NSColor.selectedTextBackgroundColor : bgColor
                fillColor.setFill()
                clearRect.fill()
            }

            switch type {
            case "bullet":
                self.drawBullet(at: NSPoint(x: x, y: y), lineHeight: lineHeight)
            case "checkboxUnchecked":
                self.drawCheckbox(at: NSPoint(x: x, y: y), lineHeight: lineHeight, checked: false)
            case "checkboxChecked":
                self.drawCheckbox(at: NSPoint(x: x, y: y), lineHeight: lineHeight, checked: true)
            case "tablePipe", "tableSeparator":
                break // Handled by drawTableBorders
            case "heading", "divider":
                break // Handled by dedicated drawing methods
            default:
                if type.hasPrefix("numberedList:") {
                    let label = String(type.dropFirst("numberedList:".count))
                    self.drawNumberedListMarker(label: label, at: NSPoint(x: x, y: y), lineHeight: lineHeight)
                }
            }
        }
    }

    // MARK: - Selection Exclusion for Markers

    // Prevents selection highlight from covering rendered marker areas (bullets, checkboxes, headings).
    // NSTextView applies selection as temporary attributes on the layout manager — we intercept
    // those calls and exclude marker ranges so only the text content gets highlighted.

    override func addTemporaryAttributes(_ attrs: [NSAttributedString.Key: Any], forCharacterRange charRange: NSRange) {
        for range in rangesExcludingMarkers(in: charRange) {
            super.addTemporaryAttributes(attrs, forCharacterRange: range)
        }
    }

    override func setTemporaryAttributes(_ attrs: [NSAttributedString.Key: Any], forCharacterRange charRange: NSRange) {
        // When clearing (empty attrs), apply to full range to ensure cleanup
        guard !attrs.isEmpty else {
            super.setTemporaryAttributes(attrs, forCharacterRange: charRange)
            return
        }
        for range in rangesExcludingMarkers(in: charRange) {
            super.setTemporaryAttributes(attrs, forCharacterRange: range)
        }
    }

    override func addTemporaryAttribute(_ attrName: NSAttributedString.Key, value: Any, forCharacterRange charRange: NSRange) {
        for range in rangesExcludingMarkers(in: charRange) {
            super.addTemporaryAttribute(attrName, value: value, forCharacterRange: range)
        }
    }

    /// Splits a character range into sub-ranges that exclude any marker-attributed text.
    private func rangesExcludingMarkers(in range: NSRange) -> [NSRange] {
        guard let textStorage, range.length > 0 else { return [range] }
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard safeRange.length > 0 else { return [] }

        var markerRanges: [NSRange] = []
        textStorage.enumerateAttribute(.listMarkerType, in: safeRange) { value, attrRange, _ in
            if value != nil {
                markerRanges.append(attrRange)
            }
        }

        guard !markerRanges.isEmpty else { return [range] }

        var result: [NSRange] = []
        var current = range.location
        let end = NSMaxRange(range)

        for marker in markerRanges.sorted(by: { $0.location < $1.location }) {
            let mStart = max(marker.location, range.location)
            let mEnd = min(NSMaxRange(marker), end)
            guard mStart < mEnd else { continue }

            if mStart > current {
                result.append(NSRange(location: current, length: mStart - current))
            }
            current = max(current, mEnd)
        }
        if current < end {
            result.append(NSRange(location: current, length: end - current))
        }

        return result
    }

    // MARK: - Block Quote Left Border

    /// Draws a colored vertical bar on the left side of block quote paragraphs.
    private func drawBlockQuoteBorders(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }

        textStorage.enumerateAttribute(.blockQuoteRange, in: charRange) { value, range, _ in
            guard value as? Bool == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

            let boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: tc)
            let barWidth: CGFloat = 3
            let barX = origin.x + boundingRect.origin.x - 10
            let barY = origin.y + boundingRect.origin.y + 2
            let barHeight = boundingRect.height - 4

            let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
            NSColor(AppThemeConstants.accent).withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    // MARK: - Divider (Horizontal Rule)

    /// Draws a horizontal line for thematic breaks (---) instead of showing text.
    private func drawDividers(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }

        textStorage.enumerateAttribute(.dividerRange, in: charRange) { value, range, _ in
            guard value as? Bool == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let containerWidth = tc.size.width
            let lineY = origin.y + lineRect.midY
            let inset: CGFloat = 4

            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: origin.x + inset, y: lineY))
            linePath.line(to: NSPoint(x: origin.x + containerWidth - inset, y: lineY))
            linePath.lineWidth = 1
            NSColor.separatorColor.setStroke()
            linePath.stroke()
        }
    }

    // MARK: - Code Block Container

    /// Draws a rounded rectangle background behind code blocks.
    private func drawCodeBlockBackgrounds(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }

        textStorage.enumerateAttribute(.codeBlockRange, in: charRange) { value, range, _ in
            guard value as? Bool == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

            let boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: tc)
            let containerWidth = tc.size.width
            let padding: CGFloat = 8
            let bgRect = NSRect(
                x: origin.x,
                y: origin.y + boundingRect.origin.y - padding / 2,
                width: containerWidth,
                height: boundingRect.height + padding
            )

            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()
        }
    }

    /// Draws borders and language labels for code blocks after text rendering.
    private func drawCodeBlockBorders(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }

        textStorage.enumerateAttribute(.codeBlockRange, in: charRange) { value, range, _ in
            guard value as? Bool == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

            let boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: tc)
            let containerWidth = tc.size.width
            let padding: CGFloat = 8
            let bgRect = NSRect(
                x: origin.x,
                y: origin.y + boundingRect.origin.y - padding / 2,
                width: containerWidth,
                height: boundingRect.height + padding
            )

            // Border
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let borderPath = NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            // Language label pill (top-right corner)
            if let language = textStorage.attribute(.codeBlockLanguage, at: range.location, effectiveRange: nil) as? String,
               !language.isEmpty
            {
                let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
                let labelColor = NSColor.secondaryLabelColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: labelColor,
                ]
                let labelStr = NSAttributedString(string: language, attributes: attrs)
                let labelSize = labelStr.size()
                let labelPadH: CGFloat = 6
                let labelPadV: CGFloat = 2
                let pillWidth = labelSize.width + labelPadH * 2
                let pillHeight = labelSize.height + labelPadV * 2
                let pillX = bgRect.maxX - pillWidth - 8
                let pillY = bgRect.minY + 6

                let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()

                let textOrigin = NSPoint(x: pillX + labelPadH, y: pillY + labelPadV)
                labelStr.draw(at: textOrigin)
            }
        }
    }

    // MARK: - Drawing Helpers

    private func drawBullet(at point: NSPoint, lineHeight: CGFloat) {
        let diameter = AppThemeConstants.bulletDiameter
        let rect = NSRect(
            x: point.x + 2,
            y: point.y + (lineHeight - diameter) / 2,
            width: diameter,
            height: diameter
        )
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func drawNumberedListMarker(label: String, at point: NSPoint, lineHeight: CGFloat) {
        let text = "\(label)."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()
        // Right-align the number within the indent area, vertically centered
        let drawX = point.x + AppThemeConstants.listHeadIndent - size.width - 6
        let drawY = point.y + (lineHeight - size.height) / 2
        attrStr.draw(at: NSPoint(x: drawX, y: drawY))
    }

    // MARK: - Table Drawing (Notion-style grid)

    /// Draws header backgrounds before text rendering.
    private func drawTableBackgrounds(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }

        textStorage.enumerateAttribute(.tableColumnCount, in: charRange) { value, range, _ in
            guard let colCount = value as? Int, colCount > 0 else { return }

            let tableGR = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard tableGR.location != NSNotFound, tableGR.length > 0 else { return }

            // Collect visible row rects (skip collapsed separator)
            let (rowRects, pipeXPositions) = self.tableLayout(
                tableGR: tableGR, tableCharRange: range, origin: origin, tc: tc
            )
            guard rowRects.count >= 1, pipeXPositions.count >= 2,
                  let tableLeft = pipeXPositions.first,
                  let tableRight = pipeXPositions.last,
                  let lastRow = rowRects.last
            else { return }

            let tableTop = origin.y + rowRects[0].minY
            let tableBottom = origin.y + lastRow.maxY
            let tableWidth = tableRight - tableLeft
            let tableHeight = tableBottom - tableTop
            let fullTableRect = NSRect(x: tableLeft, y: tableTop, width: tableWidth, height: tableHeight)

            // Clip to rounded rect for all table backgrounds
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: fullTableRect, xRadius: 4, yRadius: 4).addClip()

            // Header background (darker shade)
            let headerRect = NSRect(
                x: tableLeft,
                y: origin.y + rowRects[0].minY,
                width: tableRight - tableLeft,
                height: rowRects[0].height
            )
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            headerRect.fill()

            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Draws the full table grid (outer border, row lines, column lines) after text rendering.
    private func drawTableBorders(forCharRange charRange: NSRange, at origin: NSPoint) {
        guard let textStorage, charRange.length > 0 else { return }
        guard let tc = textContainers.first else { return }
        let bgColor = textContainers.first?.textView?.backgroundColor ?? .textBackgroundColor

        textStorage.enumerateAttribute(.tableColumnCount, in: charRange) { value, range, _ in
            guard let colCount = value as? Int, colCount > 0 else { return }

            let tableGR = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard tableGR.location != NSNotFound, tableGR.length > 0 else { return }

            let (rowRects, pipeXPositions) = self.tableLayout(
                tableGR: tableGR, tableCharRange: range, origin: origin, tc: tc
            )
            guard rowRects.count >= 1, pipeXPositions.count >= 2,
                  let tableLeft = pipeXPositions.first,
                  let tableRight = pipeXPositions.last,
                  let lastRow = rowRects.last
            else { return }

            let tableTop = origin.y + rowRects[0].minY
            let tableBottom = origin.y + lastRow.maxY
            let tableWidth = tableRight - tableLeft
            let tableHeight = tableBottom - tableTop

            // Paint over pipe character areas with background to hide them
            self.erasePipeGlyphs(
                tableCharRange: range, origin: origin, tc: tc, bgColor: bgColor
            )

            let borderColor = NSColor.separatorColor

            // Outer border
            let tableRect = NSRect(x: tableLeft, y: tableTop, width: tableWidth, height: tableHeight)
            borderColor.setStroke()
            let outerPath = NSBezierPath(roundedRect: tableRect, xRadius: 4, yRadius: 4)
            outerPath.lineWidth = 0.5
            outerPath.stroke()

            // Horizontal row separators
            for i in 1 ..< rowRects.count {
                let rowY = origin.y + rowRects[i].minY
                let linePath = NSBezierPath()
                linePath.move(to: NSPoint(x: tableLeft, y: rowY))
                linePath.line(to: NSPoint(x: tableRight, y: rowY))
                linePath.lineWidth = 0.5
                borderColor.setStroke()
                linePath.stroke()
            }

            // Vertical column separators (skip first and last pipes — they're the outer borders)
            for i in 1 ..< (pipeXPositions.count - 1) {
                let lineX = pipeXPositions[i]
                let linePath = NSBezierPath()
                linePath.move(to: NSPoint(x: lineX, y: tableTop))
                linePath.line(to: NSPoint(x: lineX, y: tableBottom))
                linePath.lineWidth = 0.5
                borderColor.setStroke()
                linePath.stroke()
            }
        }
    }

    /// Computes row rectangles and pipe X positions for a table range.
    private func tableLayout(
        tableGR: NSRange, tableCharRange: NSRange, origin: NSPoint, tc: NSTextContainer
    ) -> (rowRects: [NSRect], pipeXPositions: [CGFloat]) {
        guard let textStorage else { return ([], []) }

        // Collect line fragment rects (rows), skipping collapsed separator
        var rowRects: [NSRect] = []
        var glyphIdx = tableGR.location
        while glyphIdx < NSMaxRange(tableGR) {
            var effectiveRange = NSRange()
            let lineRect = lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &effectiveRange)
            // Skip collapsed rows (separator with hidden font has height < 3)
            if lineRect.height > 3 {
                rowRects.append(lineRect)
            }
            glyphIdx = NSMaxRange(effectiveRange)
        }

        // Find pipe X positions from the first visible row (header)
        guard let headerRect = rowRects.first else { return (rowRects, []) }
        var pipeXPositions: [CGFloat] = []

        textStorage.enumerateAttribute(.listMarkerType, in: tableCharRange) { markerValue, markerRange, _ in
            guard let type = markerValue as? String, type == "tablePipe" else { return }
            let pipeGR = self.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            guard pipeGR.location != NSNotFound, pipeGR.length > 0 else { return }

            let pipeLineRect = self.lineFragmentRect(forGlyphAt: pipeGR.location, effectiveRange: nil)
            // Only from header row
            if abs(pipeLineRect.minY - headerRect.minY) < 1 {
                let pipeBounds = self.boundingRect(forGlyphRange: pipeGR, in: tc)
                let pipeMidX = origin.x + pipeBounds.midX
                pipeXPositions.append(pipeMidX)
            }
        }

        pipeXPositions.sort()
        return (rowRects, pipeXPositions)
    }

    /// Paints background over pipe character glyphs to hide them.
    private func erasePipeGlyphs(
        tableCharRange: NSRange, origin: NSPoint, tc: NSTextContainer, bgColor: NSColor
    ) {
        guard let textStorage else { return }

        textStorage.enumerateAttribute(.listMarkerType, in: tableCharRange) { markerValue, markerRange, _ in
            guard let type = markerValue as? String, type == "tablePipe" else { return }
            let pipeGR = self.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            guard pipeGR.location != NSNotFound, pipeGR.length > 0 else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: pipeGR.location, effectiveRange: nil)
            let pipeBounds = self.boundingRect(forGlyphRange: pipeGR, in: tc)
            let eraseRect = NSRect(
                x: origin.x + pipeBounds.origin.x,
                y: origin.y + lineRect.origin.y,
                width: pipeBounds.width + 1,
                height: lineRect.height
            )
            bgColor.setFill()
            eraseRect.fill()
        }
    }

    private func drawCheckbox(at point: NSPoint, lineHeight: CGFloat, checked: Bool) {
        let size = AppThemeConstants.checkboxSize
        let rect = NSRect(
            x: point.x + 1,
            y: point.y + (lineHeight - size) / 2,
            width: size,
            height: size
        )
        let cr = AppThemeConstants.checkboxCornerRadius

        if checked {
            NSColor(AppThemeConstants.accent).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr).fill()

            // Checkmark
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7))
            check.line(to: NSPoint(x: rect.minX + 5.5, y: rect.minY + 10))
            check.line(to: NSPoint(x: rect.minX + 11, y: rect.minY + 4))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            let borderRect = rect.insetBy(dx: 0.75, dy: 0.75)
            NSColor.tertiaryLabelColor.setStroke()
            let path = NSBezierPath(roundedRect: borderRect, xRadius: cr, yRadius: cr)
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}
