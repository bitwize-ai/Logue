import Foundation

/// Remembers the language last chosen in a code block, so the next one starts there.
///
/// Someone writing a document full of Swift snippets should pick "Swift" once, not once per
/// block. Stored in `UserDefaults` rather than held in memory so the preference survives a
/// relaunch, and read through a plain accessor rather than `@AppStorage` because the callers
/// are `BlockType.makeBlock` and the block row's menu, neither of which is a view with state.
enum CodeBlockLanguageMemory {
    /// The language a newly inserted code block should start with.
    ///
    /// Empty when nothing has been chosen yet, which is the same as "plain text" — a new block
    /// then behaves exactly as it did before this existed. A remembered value that is no longer
    /// one the highlighter supports is discarded rather than written into a fence.
    static var suggestedLanguage: String {
        guard let stored = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaultsKeys.lastCodeBlockLanguage
        )
        else { return "" }
        let isSupported = CodeSyntaxHighlighter.supportedLanguages.contains {
            $0.id.caseInsensitiveCompare(stored) == .orderedSame
        }
        return isSupported ? stored : ""
    }

    /// Records a language the user picked from the code block menu.
    ///
    /// Only called for menu choices, not for text typed into the language field: a half-typed
    /// identifier would otherwise become the default for every subsequent block.
    static func remember(_ language: String) {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: AppConstants.UserDefaultsKeys.lastCodeBlockLanguage)
    }
}
