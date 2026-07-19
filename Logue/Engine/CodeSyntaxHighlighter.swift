import AppKit

/// Lightweight regex-based syntax highlighter for code blocks.
/// Supports common languages: Swift, Python, JavaScript/TypeScript, JSON, HTML, CSS, Shell, SQL, Go, Rust, Ruby, C/C++/Java.
enum CodeSyntaxHighlighter {
    // MARK: - Token Colors

    struct TokenColors {
        let keyword: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let type: NSColor
        let function: NSColor
        let property: NSColor

        /// Dynamic token colors that automatically resolve for the current appearance.
        /// Uses `NSColor(name:dynamicProvider:)` so they update on light/dark mode changes.
        static var current: TokenColors {
            TokenColors(
                keyword: dynamicNSColor(
                    light: NSColor(red: 0.67, green: 0.05, blue: 0.57, alpha: 1.0),
                    dark: NSColor(red: 0.99, green: 0.37, blue: 0.53, alpha: 1.0)
                ),
                string: dynamicNSColor(
                    light: NSColor(red: 0.77, green: 0.10, blue: 0.09, alpha: 1.0),
                    dark: NSColor(red: 0.99, green: 0.57, blue: 0.35, alpha: 1.0)
                ),
                number: dynamicNSColor(
                    light: NSColor(red: 0.11, green: 0.36, blue: 0.73, alpha: 1.0),
                    dark: NSColor(red: 0.82, green: 0.77, blue: 0.51, alpha: 1.0)
                ),
                comment: dynamicNSColor(
                    light: NSColor(red: 0.42, green: 0.47, blue: 0.51, alpha: 1.0),
                    dark: NSColor(red: 0.47, green: 0.53, blue: 0.60, alpha: 1.0)
                ),
                type: dynamicNSColor(
                    light: NSColor(red: 0.11, green: 0.36, blue: 0.73, alpha: 1.0),
                    dark: NSColor(red: 0.40, green: 0.72, blue: 0.99, alpha: 1.0)
                ),
                function: dynamicNSColor(
                    light: NSColor(red: 0.15, green: 0.49, blue: 0.36, alpha: 1.0),
                    dark: NSColor(red: 0.71, green: 0.84, blue: 0.38, alpha: 1.0)
                ),
                property: dynamicNSColor(
                    light: NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0),
                    dark: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
                )
            )
        }

        private static func dynamicNSColor(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        }
    }

    // MARK: - Token Rules

    private struct TokenRule {
        let pattern: String
        let options: NSRegularExpression.Options
        let colorKey: KeyPath<TokenColors, NSColor>

        init(_ pattern: String, _ colorKey: KeyPath<TokenColors, NSColor>, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.colorKey = colorKey
            self.options = options
        }
    }

    // MARK: - Language Keywords

    private static let swiftKeywords = [
        "import|func|var|let|class|struct|enum|protocol|extension|return",
        "if|else|guard|switch|case|default|for|while|repeat|break|continue",
        "throw|throws|try|catch|defer|async|await|actor|some|any|where|in|as|is",
        "nil|true|false|self|Self|super|init|deinit|typealias|associatedtype",
        "static|private|public|internal|fileprivate|open|override|mutating|nonmutating",
        "final|lazy|weak|unowned|optional|required|convenience",
        "willSet|didSet|get|set|inout|@Published|@State|@Binding|@Observable|@MainActor|@Environment",
    ].joined(separator: "|")

    private static let pythonKeywords = [
        "import|from|def|class|return|if|elif|else|for|while|break|continue",
        "try|except|finally|raise|with|as|lambda|yield|pass|assert|del",
        "and|or|not|is|in|True|False|None|self|async|await|global|nonlocal",
    ].joined(separator: "|")

    private static let jsKeywords = [
        "import|export|from|function|const|let|var|class|extends|return",
        "if|else|for|while|do|break|continue|switch|case|default",
        "try|catch|finally|throw|new|this|typeof|instanceof|void|delete",
        "in|of|async|await|yield|true|false|null|undefined|super|static|get|set",
    ].joined(separator: "|")

    private static let goKeywords = [
        "package|import|func|var|const|type|struct|interface|return",
        "if|else|for|range|switch|case|default|break|continue|go|defer|select",
        "chan|map|make|new|true|false|nil|error|string|int|bool|byte|rune|float64|float32",
    ].joined(separator: "|")

    private static let rustKeywords = [
        "use|mod|fn|let|mut|const|struct|enum|impl|trait|return",
        "if|else|for|while|loop|break|continue|match|self|Self|super",
        "pub|crate|async|await|move|ref|where|type|true|false",
        "None|Some|Ok|Err|unsafe|extern|dyn|as|in",
    ].joined(separator: "|")

    private static let sqlKeywords = [
        "SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE",
        "CREATE|TABLE|ALTER|DROP|INDEX|JOIN|LEFT|RIGHT|INNER|OUTER|ON",
        "AND|OR|NOT|NULL|IS|IN|LIKE|BETWEEN|ORDER|BY|GROUP|HAVING",
        "LIMIT|OFFSET|UNION|ALL|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX|EXISTS",
        "CASE|WHEN|THEN|ELSE|END",
    ].joined(separator: "|")

    private static let shellKeywords = [
        "if|then|else|elif|fi|for|while|do|done|case|esac",
        "function|return|exit|echo|export|source|alias|unset",
        "local|readonly|shift|set|unset|trap|eval|exec|true|false",
    ].joined(separator: "|")

    private static let cKeywords = [
        "include|define|ifdef|ifndef|endif|pragma|int|float|double|char|void",
        "long|short|unsigned|signed|struct|enum|union|typedef|return",
        "if|else|for|while|do|break|continue|switch|case|default|goto|sizeof",
        "static|extern|const|volatile|register|auto|inline|restrict",
        "true|false|NULL|nullptr|class|public|private|protected|virtual|override",
        "template|namespace|using|new|delete|try|catch|throw|this",
    ].joined(separator: "|")

    // MARK: - Rules by Language

    private static func rules(for language: String) -> [TokenRule] {
        let keywords: String
        switch language.lowercased() {
        case "swift": keywords = swiftKeywords
        case "python", "py": keywords = pythonKeywords
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": keywords = jsKeywords
        case "go", "golang": keywords = goKeywords
        case "rust", "rs": keywords = rustKeywords
        case "sql": keywords = sqlKeywords
        case "bash", "sh", "shell", "zsh": keywords = shellKeywords
        case "c", "cpp", "c++", "objc", "java", "cs", "csharp": keywords = cKeywords
        case "json": return jsonRules()
        case "html", "xml", "svg": return htmlRules()
        case "css", "scss", "sass": return cssRules()
        default: keywords = swiftKeywords // Default to Swift-like
        }

        return [
            // Line comments
            TokenRule(#"//[^\n]*"#, \.comment),
            // Block comments
            TokenRule(#"/\*[\s\S]*?\*/"#, \.comment, options: .dotMatchesLineSeparators),
            // Hash comments (Python, Shell, Ruby)
            TokenRule(#"#[^\n]*"#, \.comment),
            // Double-quoted strings
            TokenRule(#""(?:[^"\\]|\\.)*""#, \.string),
            // Single-quoted strings
            TokenRule(#"'(?:[^'\\]|\\.)*'"#, \.string),
            // Multi-line strings (triple quotes)
            TokenRule(#""{3}[\s\S]*?"{3}"#, \.string, options: .dotMatchesLineSeparators),
            // Numbers
            TokenRule(#"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#, \.number),
            TokenRule(#"\b0x[0-9a-fA-F]+\b"#, \.number),
            // Type names (capitalized identifiers)
            TokenRule(#"\b[A-Z][a-zA-Z0-9_]*\b"#, \.type),
            // Function calls
            TokenRule(#"\b([a-zA-Z_]\w*)\s*\("#, \.function),
            // Keywords
            TokenRule(#"\b(?:\#(keywords))\b"#, \.keyword),
        ]
    }

    private static func jsonRules() -> [TokenRule] {
        [
            TokenRule(#""(?:[^"\\]|\\.)*"\s*:"#, \.keyword), // Keys
            TokenRule(#":\s*"(?:[^"\\]|\\.)*""#, \.string), // String values
            TokenRule(#"\b\d+\.?\d*\b"#, \.number),
            TokenRule(#"\b(?:true|false|null)\b"#, \.keyword),
        ]
    }

    private static func htmlRules() -> [TokenRule] {
        [
            TokenRule(#"<!--[\s\S]*?-->"#, \.comment, options: .dotMatchesLineSeparators),
            TokenRule(#"</?[a-zA-Z][a-zA-Z0-9]*"#, \.keyword), // Tags
            TokenRule(#"\b[a-zA-Z-]+="#, \.property), // Attributes
            TokenRule(#""[^"]*""#, \.string),
            TokenRule(#"'[^']*'"#, \.string),
            TokenRule(#">"#, \.keyword),
            TokenRule(#"/>"#, \.keyword),
        ]
    }

    private static func cssRules() -> [TokenRule] {
        [
            TokenRule(#"/\*[\s\S]*?\*/"#, \.comment, options: .dotMatchesLineSeparators),
            TokenRule(#"[.#]?[a-zA-Z_-][\w-]*\s*\{"#, \.keyword), // Selectors
            TokenRule(#"\b[a-zA-Z-]+\s*:"#, \.property), // Properties
            TokenRule(#""[^"]*""#, \.string),
            TokenRule(#"'[^']*'"#, \.string),
            TokenRule(#"#[0-9a-fA-F]{3,8}\b"#, \.number), // Colors
            TokenRule(#"\b\d+\.?\d*(?:px|em|rem|%|vh|vw|pt|cm|mm)?\b"#, \.number),
        ]
    }

    // MARK: - Public API

    /// Applies syntax highlighting colors to a code block region in an NSTextStorage.
    /// - Parameters:
    ///   - textStorage: The text storage to modify
    ///   - range: The character range of the code block content (excluding fences)
    ///   - language: The language identifier (e.g., "swift", "python")
    static func highlight(_ textStorage: NSTextStorage, range: NSRange, language: String) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }

        let colors = TokenColors.current
        let tokenRules = rules(for: language)
        let codeText = (textStorage.string as NSString).substring(with: range)

        // Track highlighted ranges to avoid overlapping (first match wins)
        var highlighted = IndexSet()

        for rule in tokenRules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            let matches = regex.matches(in: codeText, range: NSRange(location: 0, length: codeText.utf16.count))

            for match in matches {
                let matchRange = match.range
                let absoluteRange = NSRange(location: range.location + matchRange.location, length: matchRange.length)

                // Skip if already highlighted
                let matchIndexRange = matchRange.location ..< (matchRange.location + matchRange.length)
                guard !highlighted.contains(integersIn: matchIndexRange) else { continue }

                guard NSMaxRange(absoluteRange) <= textStorage.length else { continue }

                let color = colors[keyPath: rule.colorKey]
                textStorage.addAttribute(.foregroundColor, value: color, range: absoluteRange)

                highlighted.insert(integersIn: matchIndexRange)
            }
        }
    }

    /// Extracts the language identifier from a code fence line (e.g., "```swift" → "swift").
    static func extractLanguage(from fenceLine: String) -> String? {
        let trimmed = fenceLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let lang = String(trimmed.drop(while: { $0 == "`" || $0 == "~" })).trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? nil : lang
    }
}
