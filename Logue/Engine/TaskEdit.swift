import Foundation

/// The rules for changing a task after it exists.
///
/// Separate from `TaskTextParser`, which turns one line of typed text into a whole task.
/// This is the other direction: a user adjusting one field of a task they already have. Both
/// end up writing the same file, so both are held to the same limits — a title edited in the
/// inspector reaches a filename and an LLM prompt exactly like a captured one does, and a
/// second, laxer entrance is how a sanitisation boundary stops being one.
enum TaskEdit {
    // MARK: - Tags

    /// A typed tag, or `nil` when it is not one.
    ///
    /// Accepts the hash or omits it, because a field labelled "tag" invites both and
    /// silently keeping a `#` would produce two tags that look identical in the list.
    /// Returns `nil` rather than a cleaned-up guess: dropping the offending characters
    /// would file the task under a tag the user did not ask for.
    static func normalisedTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(
            (trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed)
                .prefix(TaskTextParser.maxTagLength)
        )
        guard !body.isEmpty,
              body.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return body
    }

    /// The tag list with `raw` added, or unchanged when it is invalid, already there, or
    /// would exceed the parser's ceiling.
    ///
    /// Deduplicated case-insensitively and keeping the existing casing, matching how capture
    /// already treats two spellings of one tag.
    static func addingTag(_ raw: String, to tags: [String]) -> [String] {
        guard let tag = normalisedTag(raw),
              tags.count < TaskTextParser.maxTags,
              !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        else { return tags }
        return tags + [tag]
    }

    static func removingTag(_ tag: String, from tags: [String]) -> [String] {
        tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }

    // MARK: - Title

    /// The task with a new, sanitised title. Every other field is left alone.
    static func renamed(_ task: TaskItem, to title: String) -> TaskItem {
        var updated = task
        updated.title = TaskTextParser.sanitisedTitle(title)
        return updated
    }
}
