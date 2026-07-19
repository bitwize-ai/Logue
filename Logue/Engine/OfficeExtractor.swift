import Foundation
import os.log

/// Extracts visible text from Microsoft Office Open XML documents
/// (`.xlsx`, `.docx`, `.pptx`) using `ZIPArchiveReader` + `XMLParser`.
///
/// Strategy:
/// - **xlsx**: read `xl/sharedStrings.xml` (string pool) and each
///   `xl/worksheets/sheetN.xml`. Cells reference shared strings by index;
///   inline numeric / boolean / date cells carry their value in `<v>`.
/// - **docx**: walk `word/document.xml` and concatenate every `<w:t>` text run.
///   `<w:p>` paragraph boundaries become newlines.
/// - **pptx**: walk every `ppt/slides/slideN.xml` and concatenate every
///   `<a:t>` text run. Slide boundaries become double newlines.
///
/// All output is capped at `maxChars` to keep agent attachments under the
/// `<attached_file>` injection budget.
enum OfficeExtractor {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "OfficeExtractor")

    /// Returns extracted text or nil if the file isn't a recognized Office
    /// format / can't be parsed. Errors are logged at warning level — caller
    /// gets a graceful nil instead of an exception.
    static func extractText(from url: URL, maxChars: Int) -> String? {
        let ext = url.pathExtension.lowercased()
        do {
            let archive = try ZIPArchiveReader(url: url)
            switch ext {
            case "xlsx": return try extractXLSX(archive: archive, maxChars: maxChars)
            case "docx": return try extractDOCX(archive: archive, maxChars: maxChars)
            case "pptx": return try extractPPTX(archive: archive, maxChars: maxChars)
            default: return nil
            }
        } catch {
            logger.warning("Office extraction failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - XLSX

    /// Pulls every cell value across every worksheet, dereferencing the
    /// shared-string table. Cells are tab-separated within a row, rows are
    /// newline-separated, sheets are separated by `\n\n=== <name> ===\n\n`.
    private static func extractXLSX(archive: ZIPArchiveReader, maxChars: Int) throws -> String {
        // 1. Build the shared-string pool (optional — workbooks without
        //    string cells skip this part).
        var sharedStrings: [String] = []
        if let pool = try? archive.read("xl/sharedStrings.xml") {
            sharedStrings = parseXLSXSharedStrings(pool)
        }

        // 2. Find every sheet file. Workbooks may have any number of sheets;
        //    we read them in filename order which approximates sheet order.
        let sheetNames = archive.fileNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()

        var output = ""
        for sheet in sheetNames {
            guard let data = try? archive.read(sheet) else { continue }
            let sheetText = parseXLSXSheet(data, sharedStrings: sharedStrings)
            if !sheetText.isEmpty {
                output += "=== \(sheet) ===\n"
                output += sheetText
                output += "\n\n"
                if output.count >= maxChars {
                    break
                }
            }
        }
        return String(output.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `xl/sharedStrings.xml`. Each `<si>` element contains one
    /// shared string, made up of one or more `<t>` text runs.
    private static func parseXLSXSharedStrings(_ data: Data) -> [String] {
        let delegate = SharedStringsDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    /// Parses one worksheet. Cells inside rows: `<c r="A1" t="s"><v>3</v></c>`
    /// (where `t="s"` means the value is an index into the shared-string pool).
    /// Inline strings: `<c t="inlineStr"><is><t>foo</t></is></c>`.
    private static func parseXLSXSheet(_ data: Data, sharedStrings: [String]) -> String {
        let delegate = XLSXSheetDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.output
    }

    // MARK: - DOCX

    private static func extractDOCX(archive: ZIPArchiveReader, maxChars: Int) throws -> String {
        guard let data = try? archive.read("word/document.xml") else { return "" }
        let delegate = WordTextDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return String(delegate.output.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - PPTX

    private static func extractPPTX(archive: ZIPArchiveReader, maxChars: Int) throws -> String {
        let slides = archive.fileNames
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted(by: pptxSlideSort)

        var output = ""
        for (idx, slide) in slides.enumerated() {
            guard let data = try? archive.read(slide) else { continue }
            let delegate = PPTXSlideDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            if !delegate.output.isEmpty {
                output += "--- Slide \(idx + 1) ---\n"
                output += delegate.output
                output += "\n\n"
                if output.count >= maxChars {
                    break
                }
            }
        }
        return String(output.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sort slide files numerically: `slide2.xml` before `slide10.xml`.
    /// Lexical sort would put `slide10.xml` before `slide2.xml`.
    private static func pptxSlideSort(_ lhs: String, _ rhs: String) -> Bool {
        func slideNumber(_ name: String) -> Int {
            // "ppt/slides/slide12.xml" → 12
            let base = name
                .replacingOccurrences(of: "ppt/slides/slide", with: "")
                .replacingOccurrences(of: ".xml", with: "")
            return Int(base) ?? 0
        }
        return slideNumber(lhs) < slideNumber(rhs)
    }
}

// MARK: - XML Parser delegates

/// Pulls every `<t>` text run inside `<si>` (shared string item).
private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var inItem = false
    private var inText = false
    private var currentItem = ""
    private var currentText = ""

    func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String]) {
        switch name {
        case "si": inItem = true; currentItem = ""
        case "t": inText = true; currentText = ""
        default: break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
        switch name {
        case "t":
            if inItem {
                currentItem += currentText
            }
            inText = false
        case "si":
            strings.append(currentItem)
            inItem = false
        default: break
        }
    }
}

/// Walks `<row><c><v>...</v></c>...</row>` extracting cell values, dereferencing
/// shared-string indexes when `t="s"`. Skips formula `<f>` text — we want the
/// *value*, not the formula.
private final class XLSXSheetDelegate: NSObject, XMLParserDelegate {
    var output = ""
    private let sharedStrings: [String]
    private var rowCells: [String] = []
    private var inCell = false
    private var inValue = false
    private var inInlineString = false
    private var currentCellType = ""
    private var currentValue = ""

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes attrs: [String: String]) {
        switch name {
        case "row": rowCells = []
        case "c":
            inCell = true
            currentCellType = attrs["t"] ?? ""
            currentValue = ""
        case "v":
            if inCell {
                inValue = true
            }
        case "is":
            if inCell {
                inInlineString = true
            }
        case "t":
            if inInlineString {
                inValue = true
            }
        default: break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inValue {
            currentValue += string
        }
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
        switch name {
        case "v", "t":
            inValue = false
        case "is":
            inInlineString = false
        case "c":
            // Resolve shared-string index if needed.
            if currentCellType == "s",
               let idx = Int(currentValue.trimmingCharacters(in: .whitespacesAndNewlines)),
               idx >= 0, idx < sharedStrings.count
            {
                rowCells.append(sharedStrings[idx])
            } else if !currentValue.isEmpty {
                rowCells.append(currentValue)
            }
            inCell = false
            currentCellType = ""
            currentValue = ""
        case "row":
            if !rowCells.isEmpty {
                output += rowCells.joined(separator: "\t") + "\n"
            }
        default: break
        }
    }
}

/// Walks docx body, concatenating every `<w:t>` text run. Paragraph
/// boundaries (`<w:p>`) become newlines. `<w:tab/>` becomes a tab.
private final class WordTextDelegate: NSObject, XMLParserDelegate {
    var output = ""
    private var inText = false
    private var currentText = ""

    func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName qname: String?, attributes _: [String: String]) {
        let local = qname ?? name
        if local == "w:t" {
            inText = true
            currentText = ""
        } else if local == "w:tab" {
            output += "\t"
        } else if local == "w:br" {
            output += "\n"
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName qname: String?) {
        let local = qname ?? name
        if local == "w:t" {
            output += currentText
            inText = false
        } else if local == "w:p" {
            output += "\n"
        }
    }
}

/// Walks pptx slide XML, concatenating every `<a:t>` text run (Office's
/// drawingML namespace uses `a:` for shape text). Paragraph (`<a:p>`) ends
/// become newlines.
private final class PPTXSlideDelegate: NSObject, XMLParserDelegate {
    var output = ""
    private var inText = false
    private var currentText = ""

    func parser(_: XMLParser, didStartElement _: String, namespaceURI _: String?, qualifiedName qname: String?, attributes _: [String: String]) {
        if qname == "a:t" {
            inText = true
            currentText = ""
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }

    func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName qname: String?) {
        if qname == "a:t" {
            output += currentText
            inText = false
        } else if qname == "a:p" {
            output += "\n"
        }
    }
}
