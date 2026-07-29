import Foundation

/// A frontmatter value. Only the shapes the mirror needs — scalars and string lists.
enum FrontmatterValue: Equatable, Sendable {
    case scalar(String)
    case list([String])
}

/// Reads and writes the YAML frontmatter block of a markdown file.
///
/// Deliberately a small hand-rolled subset rather than a general YAML implementation:
/// the mirror only emits scalars and string lists, and a narrow writer we fully
/// control is easier to keep byte-stable than a general one. These files are
/// git-tracked, so unstable key order or quoting would mean a diff on every save.
///
/// Parsing is correspondingly forgiving: anything it does not understand is left
/// alone rather than throwing, because these files are meant to be hand-editable.
enum MarkdownFrontmatter {
    private static let fence = "---"
    private static let listIndent = "  - "

    // MARK: - Rendering

    /// Renders an ordered field list. Order is the caller's, so output is stable.
    ///
    /// Empty scalars and empty lists are omitted: a key with no value is noise in a
    /// diff and carries no information.
    static func render(_ fields: [(key: String, value: FrontmatterValue)]) -> String {
        guard !fields.isEmpty else { return "" }

        var lines = [fence]
        for (key, value) in fields {
            switch value {
            case let .scalar(raw):
                guard !raw.isEmpty else { continue }
                lines.append("\(key): \(quotedIfNeeded(raw))")
            case let .list(items):
                let usable = items.filter { !$0.isEmpty }
                guard !usable.isEmpty else { continue }
                lines.append("\(key):")
                lines += usable.map { "\(listIndent)\(quotedIfNeeded($0))" }
            }
        }
        lines.append(fence)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    /// Splits a markdown file into its frontmatter fields and its body.
    ///
    /// A missing or unterminated block yields no fields and the whole input as body,
    /// so a malformed file reads as ordinary markdown rather than losing content.
    static func parse(_ markdown: String) -> (fields: [String: FrontmatterValue], body: String) {
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == fence,
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == fence
              })
        else {
            return ([:], markdown)
        }

        let fieldLines = Array(lines[1 ..< closingIndex])
        let bodyLines = Array(lines[(closingIndex + 1)...])

        return (parseFields(fieldLines), bodyLines.joined(separator: "\n"))
    }

    // MARK: - Private

    private static func parseFields(_ lines: [String]) -> [String: FrontmatterValue] {
        var fields: [String: FrontmatterValue] = [:]
        var currentListKey: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Comments and blank lines carry nothing.
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // A list item continues the key above it.
            if trimmed.hasPrefix("- ") {
                guard let key = currentListKey else { continue }
                let item = unquoted(String(trimmed.dropFirst(2)))
                if case let .list(existing)? = fields[key] {
                    fields[key] = .list(existing + [item])
                } else {
                    fields[key] = .list([item])
                }
                continue
            }

            // `key: value`, splitting only on the first colon so URLs survive.
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex ..< separator])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            let rawValue = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // A bare key opens a list; later duplicates replace it.
                currentListKey = key
                fields.removeValue(forKey: key)
            } else {
                currentListKey = nil
                fields[key] = .scalar(unquoted(rawValue))
            }
        }

        return fields
    }

    /// Quotes only when the value would otherwise be misread.
    ///
    /// A newline is escaped rather than quoted, because no amount of quoting saves it: a value
    /// spanning two lines is two YAML lines, and the second one is read as a stray key. A title
    /// containing one — pasted from somewhere — made the document unwritable, and its verification
    /// failure was only ever a log line.
    private static func quotedIfNeeded(_ value: String) -> String {
        let value = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let needsQuoting =
            value != value.trimmingCharacters(in: .whitespaces)
                || value.contains(":")
                || value.contains("#")
                || value.contains("\"")
                || value.hasPrefix("[")
                || value.hasPrefix("-")
                || value.hasPrefix("&")
                || value.hasPrefix("*")
                || value.hasPrefix("!")

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
