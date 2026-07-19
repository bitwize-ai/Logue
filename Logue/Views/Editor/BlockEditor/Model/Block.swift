import Foundation

// MARK: - Block ID

typealias BlockID = UUID

// MARK: - List Items

struct BlockListItem: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var indent: Int

    init(id: UUID = UUID(), text: String = "", indent: Int = 0) {
        self.id = id
        self.text = text
        self.indent = indent
    }
}

struct CheckboxItem: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var isChecked: Bool
    var indent: Int

    init(id: UUID = UUID(), text: String = "", isChecked: Bool = false, indent: Int = 0) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
        self.indent = indent
    }
}

// MARK: - Block

enum Block: Identifiable {
    case paragraph(id: BlockID, text: String)
    case heading(id: BlockID, level: Int, text: String)
    case bulletList(id: BlockID, items: [BlockListItem])
    case numberedList(id: BlockID, items: [BlockListItem])
    case checkboxList(id: BlockID, items: [CheckboxItem])
    case blockQuote(id: BlockID, text: String)
    case codeBlock(id: BlockID, language: String, code: String)
    case table(id: BlockID, data: TableBlockData)
    case divider(id: BlockID)

    var id: BlockID {
        switch self {
        case let .paragraph(id, _),
             let .heading(id, _, _),
             let .bulletList(id, _),
             let .numberedList(id, _),
             let .checkboxList(id, _),
             let .blockQuote(id, _),
             let .codeBlock(id, _, _),
             let .table(id, _),
             let .divider(id):
            id
        }
    }

    /// Returns the plain text content for text-based blocks, nil for non-text blocks.
    var textContent: String? {
        get {
            switch self {
            case let .paragraph(_, text),
                 let .heading(_, _, text),
                 let .blockQuote(_, text):
                text
            case let .codeBlock(_, _, code):
                code
            default:
                nil
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            case let .paragraph(id, _):
                self = .paragraph(id: id, text: newValue)
            case let .heading(id, level, _):
                self = .heading(id: id, level: level, text: newValue)
            case let .blockQuote(id, _):
                self = .blockQuote(id: id, text: newValue)
            case let .codeBlock(id, language, _):
                self = .codeBlock(id: id, language: language, code: newValue)
            default:
                break
            }
        }
    }

    /// Whether this block type contains editable text directly (not via list items).
    var isTextBlock: Bool {
        switch self {
        case .paragraph, .heading, .blockQuote, .codeBlock:
            true
        default:
            false
        }
    }

    /// Whether this block is a list (bullet, numbered, or checkbox).
    var isListBlock: Bool {
        switch self {
        case .bulletList, .numberedList, .checkboxList:
            true
        default:
            false
        }
    }

    /// All searchable text strings in this block (paragraph text, list item texts, code, etc.).
    /// Used for suggestion mapping and scroll-to-text matching.
    var searchableTexts: [String] {
        switch self {
        case let .paragraph(_, text), let .heading(_, _, text), let .blockQuote(_, text):
            text.isEmpty ? [] : [text]
        case let .codeBlock(_, _, code):
            code.isEmpty ? [] : [code]
        case let .bulletList(_, items), let .numberedList(_, items):
            items.map(\.text).filter { !$0.isEmpty }
        case let .checkboxList(_, items):
            items.map(\.text).filter { !$0.isEmpty }
        default:
            []
        }
    }

    /// Whether this block is empty (no meaningful content).
    var isEmpty: Bool {
        switch self {
        case let .paragraph(_, text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .heading(_, _, text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .bulletList(_, items):
            items.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case let .numberedList(_, items):
            items.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case let .checkboxList(_, items):
            items.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case let .blockQuote(_, text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .codeBlock(_, _, code):
            code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .table(_, data):
            data.rows.allSatisfy { $0.allSatisfy(\.isEmpty) }
        case .divider:
            false
        }
    }
}

// MARK: - Equatable

extension Block: Equatable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        switch (lhs, rhs) {
        case let (.paragraph(lid, lt), .paragraph(rid, rt)):
            lid == rid && lt == rt
        case let (.heading(lid, ll, lt), .heading(rid, rl, rt)):
            lid == rid && ll == rl && lt == rt
        case let (.bulletList(lid, li), .bulletList(rid, ri)):
            lid == rid && li == ri
        case let (.numberedList(lid, li), .numberedList(rid, ri)):
            lid == rid && li == ri
        case let (.checkboxList(lid, li), .checkboxList(rid, ri)):
            lid == rid && li == ri
        case let (.blockQuote(lid, lt), .blockQuote(rid, rt)):
            lid == rid && lt == rt
        case let (.codeBlock(lid, ll, lc), .codeBlock(rid, rl, rc)):
            lid == rid && ll == rl && lc == rc
        case let (.table(lid, ld), .table(rid, rd)):
            lid == rid && ld === rd && ld.version == rd.version
        case let (.divider(lid), .divider(rid)):
            lid == rid
        default:
            false
        }
    }
}

// MARK: - Factory Methods

extension Block {
    static func emptyParagraph() -> Block {
        .paragraph(id: UUID(), text: "")
    }

    static func emptyHeading(level: Int = 1) -> Block {
        .heading(id: UUID(), level: level, text: "")
    }

    static func emptyBulletList() -> Block {
        .bulletList(id: UUID(), items: [BlockListItem()])
    }

    static func emptyNumberedList() -> Block {
        .numberedList(id: UUID(), items: [BlockListItem()])
    }

    static func emptyCheckboxList() -> Block {
        .checkboxList(id: UUID(), items: [CheckboxItem()])
    }

    static func emptyBlockQuote() -> Block {
        .blockQuote(id: UUID(), text: "")
    }

    static func emptyCodeBlock(language: String = "") -> Block {
        .codeBlock(id: UUID(), language: language, code: "")
    }

    static func emptyTable(columns: Int = 3, rows: Int = 2, availableWidth: CGFloat? = nil) -> Block {
        .table(id: UUID(), data: TableBlockData(columns: columns, rowCount: rows, availableWidth: availableWidth))
    }

    static func newDivider() -> Block {
        .divider(id: UUID())
    }

    /// The first list item ID for list-type blocks, nil for others.
    var firstListItemID: UUID? {
        switch self {
        case let .bulletList(_, items), let .numberedList(_, items):
            items.first?.id
        case let .checkboxList(_, items):
            items.first?.id
        default:
            nil
        }
    }
}
