import Foundation

/// A category a document belongs to — Project, Person, Meeting Note, and so on.
///
/// Types are navigation aids, not schemas: nothing is required, nothing is
/// validated. A type contributes an icon, a colour, sidebar placement, which
/// properties to pin, defaults for new documents, and an optional body template.
struct DocumentType: Equatable, Codable, Identifiable, Sendable {
    /// Longest accepted name. Names appear in the sidebar and are embedded in LLM
    /// prompts, so an unbounded name is both a layout and a prompt-budget problem.
    static let maxNameLength = 40

    /// Group label for documents without a type.
    static let untypedGroupName = "Untyped"

    var id = UUID()
    var name: String
    var symbolName: String
    var colorName: String
    /// Lower sorts earlier in the sidebar.
    var sidebarOrder: Int
    /// Property keys surfaced first in the inspector for this type.
    var pinnedProperties: [String]
    /// Properties a new document of this type starts with.
    var defaultProperties: [String: PropertyValue]
    /// Markdown seeded into a new, empty document of this type.
    var template: String?

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "doc.text",
        colorName: String = "accent",
        sidebarOrder: Int = 0,
        pinnedProperties: [String] = [],
        defaultProperties: [String: PropertyValue] = [:],
        template: String? = nil
    ) {
        self.id = id
        self.name = Self.sanitisedName(name)
        self.symbolName = symbolName
        self.colorName = colorName
        self.sidebarOrder = sidebarOrder
        self.pinnedProperties = pinnedProperties
        self.defaultProperties = defaultProperties
        self.template = template
    }

    // MARK: - Applying

    /// Returns `document` tagged with this type, seeded with its defaults.
    ///
    /// Never overwrites what the user already has: an existing property keeps its
    /// value, and a non-empty body is left completely alone. Applying a type should
    /// be safe to do to an existing document, not destructive.
    func applied(to document: WritingDocument) -> WritingDocument {
        var updated = document
        updated.setProperty(PropertyKey.type.rawValue, value: .text(name))

        for (key, value) in defaultProperties where updated.property(key) == nil {
            updated.setProperty(key, value: value)
        }

        if let template,
           document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            updated.body = template
        }

        return updated
    }

    // MARK: - Registry helpers

    /// Sidebar order, then name, so the list is stable and predictable.
    static func ordered(_ types: [DocumentType]) -> [DocumentType] {
        types.sorted { lhs, rhs in
            lhs.sidebarOrder == rhs.sidebarOrder
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.sidebarOrder < rhs.sidebarOrder
        }
    }

    static func matching(name: String, in types: [DocumentType]) -> DocumentType? {
        types.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Groups documents by type name, with untyped documents under a single label.
    static func grouped(_ documents: [WritingDocument]) -> [String: [WritingDocument]] {
        Dictionary(grouping: documents) { $0.typeName ?? untypedGroupName }
    }

    // MARK: - Private

    /// Collapses a name to a single safe line, falling back rather than allowing an
    /// unnamed type.
    private static func sanitisedName(_ raw: String) -> String {
        let collapsed = raw.filter { character in
            !character.isNewline && character.unicodeScalars.allSatisfy { scalar in
                scalar.properties.generalCategory != .control
            }
        }
        let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Untitled Type" }
        return String(trimmed.prefix(maxNameLength))
    }
}

// MARK: - Document convenience

extension WritingDocument {
    /// The name of this document's type, from its `type` property.
    var typeName: String? {
        guard case let .text(name)? = property(PropertyKey.type.rawValue),
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return name
    }
}
