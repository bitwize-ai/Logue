import AppKit
import UniformTypeIdentifiers

enum PDFExportService {
    // MARK: - A4 Layout Constants

    private static let pageWidth: CGFloat = 595.28
    private static let pageHeight: CGFloat = 841.89
    private static let marginX: CGFloat = 56
    private static let marginTop: CGFloat = 64 // header + gap above content
    private static let marginBottom: CGFloat = 56 // footer + gap below content
    private static var contentWidth: CGFloat {
        pageWidth - marginX * 2
    }

    private static var contentHeight: CGFloat {
        pageHeight - marginTop - marginBottom
    }

    private static let brandColor = NSColor(red: 0, green: 0.5, blue: 0.5, alpha: 1)
    /// Compile-time constant URL
    private static let logueURL = URL(string: "https://bitwize.ai/")!

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Public

    @MainActor
    static func export(document: WritingDocument) {
        guard let pdfData = renderPDFData(document: document) else { return }

        // --- Save panel ---
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.title + ".pdf"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            pdfData.write(to: url, atomically: true)
        }
    }

    /// Renders a document to PDF bytes without showing a save panel. Used by the agent
    /// `export_document_pdf` tool. Returns nil if rendering fails.
    @MainActor
    static func renderPDFData(document: WritingDocument) -> NSData? {
        let bodyContent = buildBodyContent(document: document)

        // --- Paginate with TextKit ---
        let textStorage = NSTextStorage(attributedString: bodyContent)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        let totalGlyphs = layoutManager.numberOfGlyphs

        if totalGlyphs > 0 {
            repeat {
                let tc = NSTextContainer(size: NSSize(width: contentWidth, height: contentHeight))
                tc.lineFragmentPadding = 0
                layoutManager.addTextContainer(tc)
                containers.append(tc)
                layoutManager.ensureLayout(for: tc)
                let range = layoutManager.glyphRange(for: tc)
                if range.length == 0 {
                    containers.removeLast(); break
                }
            } while !containers.isEmpty &&
                NSMaxRange(layoutManager.glyphRange(for: containers[containers.count - 1])) < totalGlyphs
        }

        let totalPages = max(containers.count, 1)

        // --- Build multi-page PDF ---
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        let pageCount = max(containers.count, 1)

        for i in 0 ..< pageCount {
            ctx.beginPDFPage(nil)

            // Flip to top-left origin for drawing
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageHeight)
            ctx.scaleBy(x: 1, y: -1)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

            drawHeader(ctx: ctx)

            // Draw body text for this page
            if i < containers.count {
                let glyphRange = layoutManager.glyphRange(for: containers[i])
                if glyphRange.length > 0 {
                    let origin = NSPoint(x: marginX, y: marginTop)
                    layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
                    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
                }
            }

            drawFooter(ctx: ctx, page: i + 1, of: totalPages)

            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

            // Hyperlink annotations (PDF coords, bottom-left origin)
            addLinkAnnotations(ctx: ctx)

            ctx.endPDFPage()
        }

        ctx.closePDF()
        return pdfData
    }

    // MARK: - Body Content (flows across pages)

    private static func buildBodyContent(document: WritingDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Title
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let titlePara = NSMutableParagraphStyle()
            titlePara.paragraphSpacing = 4
            result.append(NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: titlePara,
            ]))
        }

        // Created + Exported dates
        let created = dateFormatter.string(from: document.createdAt)
        let exported = dateFormatter.string(from: Date())
        let metaPara = NSMutableParagraphStyle()
        metaPara.paragraphSpacing = 16
        result.append(NSAttributedString(string: "Created: \(created)   |   Exported: \(exported)\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray,
            .paragraphStyle: metaPara,
        ]))

        // Body text
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineSpacing = 4
        result.append(NSAttributedString(string: document.body, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.black,
            .paragraphStyle: bodyPara,
        ]))

        return result
    }

    // MARK: - Header (drawn in flipped coords, every page)

    private static func drawHeader(ctx: CGContext) {
        // "Logue" brand top-left
        let brand = NSAttributedString(string: "Logue", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: brandColor,
        ])
        brand.draw(at: NSPoint(x: marginX, y: 20))

        // "bitwize.ai" subtle tagline next to it
        let tag = NSAttributedString(string: "  —  bitwize.ai", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray,
        ])
        let brandSize = brand.size()
        tag.draw(at: NSPoint(x: marginX + brandSize.width, y: 22))

        // Separator line
        let lineY = marginTop - 8
        ctx.setStrokeColor(NSColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginX, y: lineY))
        ctx.addLine(to: CGPoint(x: pageWidth - marginX, y: lineY))
        ctx.strokePath()
    }

    // MARK: - Footer (drawn in flipped coords, every page)

    private static func drawFooter(ctx: CGContext, page: Int, of total: Int) {
        let lineY = pageHeight - marginBottom + 12

        // Separator line
        ctx.setStrokeColor(NSColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginX, y: lineY))
        ctx.addLine(to: CGPoint(x: pageWidth - marginX, y: lineY))
        ctx.strokePath()

        let textY = lineY + 12

        // Page number — centered
        let pageStr = NSAttributedString(string: "Page \(page) of \(total)", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray,
        ])
        let pageSize = pageStr.size()
        pageStr.draw(at: NSPoint(x: (pageWidth - pageSize.width) / 2, y: textY))

        // "Exported with Logue" — right-aligned
        let label = NSMutableAttributedString(string: "Exported with ", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray,
        ])
        label.append(NSAttributedString(string: "Logue", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: brandColor,
        ]))
        let labelSize = label.size()
        label.draw(at: NSPoint(x: pageWidth - marginX - labelSize.width, y: textY))
    }

    // MARK: - PDF Link Annotations (unflipped PDF coords)

    private static func addLinkAnnotations(ctx: CGContext) {
        // Header "Logue" link
        let headerRect = CGRect(x: marginX, y: pageHeight - 34, width: 80, height: 16)
        ctx.setURL(logueURL as CFURL, for: headerRect)

        // Footer "Logue" link (right-aligned area)
        let footerRect = CGRect(x: pageWidth - marginX - 120, y: 24, width: 120, height: 16)
        ctx.setURL(logueURL as CFURL, for: footerRect)
    }
}
