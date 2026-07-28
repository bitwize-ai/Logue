import Foundation

/// A typed value for a document property.
///
/// Encodes as a tagged object (`{"kind": "...", "value": ...}`) rather than relying
/// on Swift's default enum encoding, so the persisted JSON stays readable and a
/// future plain-markdown representation can map it onto YAML frontmatter.
enum PropertyValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case date(Date)
    case boolean(Bool)
    case list([String])
    /// A kind this build does not know, kept exactly as written so the round trip loses nothing.
    ///
    /// Decoding used to throw on an unrecognised `kind`, and that throw propagated out of
    /// `[String: PropertyValue]`, out of `WritingDocument.init(from:)`, and into the per-file
    /// `catch` in `DocumentStore` that skips the file — so a document written by a newer build
    /// *disappeared from the library* on an older one. `relationships` is stored as raw strings for
    /// exactly this reason; this had no such tolerance.
    case unknown(kind: String, value: PreservedJSON)

    /// How the value reads in the UI.
    var displayString: String {
        switch self {
        case let .text(value):
            value
        case let .number(value):
            Self.formatted(number: value)
        case let .date(value):
            Self.dateFormatter.string(from: value)
        case let .boolean(value):
            value ? "Yes" : "No"
        case let .list(values):
            values.joined(separator: ", ")
        case let .unknown(_, value):
            value.displayString
        }
    }

    /// Whole numbers read better without a trailing `.0`.
    private static func formatted(number value: Double) -> String {
        guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
        return String(Int(value))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Codable

extension PropertyValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case text, number, date, boolean, list
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .number(value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .date(value):
            try container.encode(Kind.date, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .boolean(value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .list(values):
            try container.encode(Kind.list, forKey: .kind)
            try container.encode(values, forKey: .value)
        case let .unknown(kind, value):
            // The original tag and payload, unchanged: a newer build must find what it wrote.
            try container.encode(kind, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            self = .unknown(
                kind: rawKind,
                value: (try? container.decode(PreservedJSON.self, forKey: .value)) ?? .null
            )
            return
        }

        switch kind {
        case .text:
            self = try .text(container.decode(String.self, forKey: .value))
        case .number:
            self = try .number(container.decode(Double.self, forKey: .value))
        case .date:
            self = try .date(container.decode(Date.self, forKey: .value))
        case .boolean:
            self = try .boolean(container.decode(Bool.self, forKey: .value))
        case .list:
            self = try .list(container.decode([String].self, forKey: .value))
        }
    }
}

// MARK: - Keys

/// Well-known property names, plus sanitisation for user-supplied ones.
///
/// Keys use frontmatter-style snake_case so a future plain-markdown representation
/// persists them unchanged.
enum PropertyKey: String, CaseIterable, Sendable {
    case type
    case status
    case url
    case dueDate = "due_date"
    case author
    case priority

    /// Longest accepted key. Keys are shown in the UI and embedded in LLM prompts,
    /// so an unbounded key is both a layout and a prompt-budget problem.
    static let maxKeyLength = 40

    var label: String {
        switch self {
        case .type: "Type"
        case .status: "Status"
        case .url: "URL"
        case .dueDate: "Due date"
        case .author: "Author"
        case .priority: "Priority"
        }
    }

    /// Suggested value shape, so the editor can offer the right control.
    var suggestedKind: String {
        switch self {
        case .dueDate: "date"
        default: "text"
        }
    }

    /// Normalises a user-typed key into a frontmatter name.
    ///
    /// Returns `nil` for a key that is empty after cleaning, or that starts with `_`
    /// — underscore-prefixed names are reserved for system metadata, and letting a
    /// user create one would let them shadow internal fields.
    static func sanitisedKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("_") else { return nil }

        let lowered = trimmed.lowercased()
        var cleaned = ""
        for character in lowered {
            if character.isLetter || character.isNumber {
                cleaned.append(character)
            } else if character == " " || character == "-" || character == "_" {
                cleaned.append("_")
            }
        }

        // Collapse runs of underscores and trim them from the ends.
        while cleaned.contains("__") {
            cleaned = cleaned.replacingOccurrences(of: "__", with: "_")
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxKeyLength))
    }
}
