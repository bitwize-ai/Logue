import Foundation

// MARK: - ParsedTask

/// What quick capture understood from one line of text.
struct ParsedTask: Equatable, Sendable {
    var title: String
    var priority: TaskPriority
    var dueDate: Date?
    var tags: [String]
    var recurrence: TaskRecurrence?
}

// MARK: - TaskTextParser

/// Turns `Send the deck tomorrow #launch !` into a task.
///
/// Each rule consumes the tokens it matched, and whatever survives is the title.
///
/// Deliberately token-based rather than regular-expression based. The alternative means
/// `NSRegularExpression`, which reports `NSRange` in UTF-16 offsets — mixing those with
/// Swift's grapheme indices is the single hazard this codebase has been bitten by, and a
/// parser fed emoji is precisely where it would bite again.
///
/// `now` and `calendar` are parameters rather than `Date()` and `.current`: a parser that
/// reads the clock cannot be tested, and "friday" has to mean the same thing twice.
enum TaskTextParser {
    /// Beyond this a "tag" is a paste accident.
    static let maxTags = 5
    static let maxTagLength = 32
    /// A year out. Anything further is a typo, and large values overflow date arithmetic.
    static let maxRelativeDays = 365

    private static let fallbackTitle = "Untitled task"

    /// Weekday symbols mapped to `Calendar`'s 1-based Sunday-first numbering.
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // POSIX, so a user's regional calendar cannot change what an ISO date means.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Entry point

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ParsedTask {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var tags: [String] = []
        var priority = TaskPriority.medium
        var recurrence: TaskRecurrence?
        var dueDate: Date?

        tokens = extractingTags(from: tokens, into: &tags)
        tokens = extractingPriority(from: tokens, into: &priority)
        // Before the due date, so `every week` is not consumed by the `week` in `next week`.
        tokens = extractingRecurrence(from: tokens, into: &recurrence)
        tokens = extractingDueDate(from: tokens, into: &dueDate, now: now, calendar: calendar)

        return ParsedTask(
            title: sanitisedTitle(tokens.joined(separator: " ")),
            priority: priority,
            dueDate: dueDate,
            tags: tags,
            recurrence: recurrence
        )
    }

    // MARK: - Title

    /// Strips control characters, collapses whitespace and bounds the length.
    ///
    /// This value reaches both a filename and an LLM prompt, so it is a sanitisation
    /// boundary rather than cosmetics.
    static func sanitisedTitle(_ raw: String) -> String {
        let cleaned = raw
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallbackTitle }
        return String(cleaned.prefix(TaskItem.maxTitleLength))
    }

    // MARK: - Tags

    private static func extractingTags(from tokens: [String], into tags: inout [String]) -> [String] {
        var seen = Set<String>()
        var remaining: [String] = []

        for token in tokens {
            guard token.hasPrefix("#") else {
                remaining.append(token)
                continue
            }
            let body = String(token.dropFirst().prefix(maxTagLength))
            // A bare `#`, or one followed by punctuation, is not a tag — `Fix issue # 42`
            // should keep its hash rather than gaining a mystery tag.
            guard !body.isEmpty,
                  body.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                  tags.count < maxTags
            else {
                remaining.append(token)
                continue
            }
            // Deduplicated case-insensitively, keeping the casing the user typed first.
            guard seen.insert(body.lowercased()).inserted else { continue }
            tags.append(body)
        }
        return remaining
    }

    // MARK: - Priority

    /// A trailing run of `!` means high.
    ///
    /// Note this deliberately differs from the tool this borrows from, where `!` means
    /// *low* and `!!` means high. A person typing `!` means urgent; low priority is set
    /// from the UI instead.
    private static func extractingPriority(
        from tokens: [String], into priority: inout TaskPriority
    ) -> [String] {
        guard let last = tokens.last, !last.isEmpty, last.allSatisfy({ $0 == "!" }) else {
            return tokens
        }
        priority = .high
        return Array(tokens.dropLast())
    }

    // MARK: - Recurrence

    private static func extractingRecurrence(
        from tokens: [String], into recurrence: inout TaskRecurrence?
    ) -> [String] {
        // Single words first: `daily`, `weekly`, `monthly`.
        if let index = tokens.firstIndex(where: {
            ["daily", "weekly", "monthly"].contains($0.lowercased())
        }) {
            recurrence = TaskRecurrence.parse(tokens[index])
            var remaining = tokens
            remaining.remove(at: index)
            return remaining
        }

        guard let start = tokens.firstIndex(where: { $0.lowercased() == "every" }) else {
            return tokens
        }

        // `every week` / `every 2 weeks`
        let afterEvery = start + 1
        guard afterEvery < tokens.count else { return tokens }

        if let unit = unit(from: tokens[afterEvery]) {
            recurrence = TaskRecurrence(unit: unit, interval: 1)
            return removing(tokens, from: start, count: 2)
        }

        let unitIndex = afterEvery + 1
        guard let count = Int(tokens[afterEvery]), unitIndex < tokens.count,
              let unit = unit(from: tokens[unitIndex])
        else { return tokens }

        recurrence = TaskRecurrence(unit: unit, interval: count)
        return removing(tokens, from: start, count: 3)
    }

    /// `week` / `weeks` → `.week`.
    private static func unit(from token: String) -> TaskRecurrence.Unit? {
        let lowered = token.lowercased()
        let word = lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
        return TaskRecurrence.Unit(rawValue: word)
    }

    private static func removing(_ tokens: [String], from index: Int, count: Int) -> [String] {
        var remaining = tokens
        let end = min(index + count, remaining.count)
        remaining.removeSubrange(index ..< end)
        return remaining
    }

    // MARK: - Due date

    private static func extractingDueDate(
        from tokens: [String], into dueDate: inout Date?, now: Date, calendar: Calendar
    ) -> [String] {
        let startOfToday = calendar.startOfDay(for: now)

        if let remaining = extractingIntervalPhrase(
            tokens, into: &dueDate, startOfToday: startOfToday, calendar: calendar
        ) {
            return remaining
        }

        for (index, token) in tokens.enumerated() {
            guard let resolved = singleTokenDate(
                token, startOfToday: startOfToday, calendar: calendar
            ) else { continue }
            dueDate = resolved
            return removing(tokens, from: index, count: 1)
        }
        return tokens
    }

    /// `in 3 days` / `next week`, or `nil` when neither is present.
    private static func extractingIntervalPhrase(
        _ tokens: [String], into dueDate: inout Date?, startOfToday: Date, calendar: Calendar
    ) -> [String]? {
        if let start = tokens.firstIndex(where: { $0.lowercased() == "in" }),
           start + 2 < tokens.count,
           let count = Int(tokens[start + 1]),
           let unit = unit(from: tokens[start + 2]) {
            let clamped = min(max(count, 1), maxRelativeDays)
            dueDate = TaskRecurrence(unit: unit, interval: clamped)
                .nextDueDate(after: startOfToday, calendar: calendar)
            return removing(tokens, from: start, count: 3)
        }

        if let start = tokens.firstIndex(where: { $0.lowercased() == "next" }),
           start + 1 < tokens.count,
           let unit = unit(from: tokens[start + 1]) {
            dueDate = TaskRecurrence(unit: unit, interval: 1)
                .nextDueDate(after: startOfToday, calendar: calendar)
            return removing(tokens, from: start, count: 2)
        }
        return nil
    }

    /// `today`, `tomorrow`, a weekday name, or an ISO date.
    private static func singleTokenDate(
        _ token: String, startOfToday: Date, calendar: Calendar
    ) -> Date? {
        let word = token.lowercased()
        if word == "today" { return startOfToday }
        if word == "tomorrow" { return calendar.date(byAdding: .day, value: 1, to: startOfToday) }

        if let weekday = weekdays[word] {
            return nextOccurrence(ofWeekday: weekday, after: startOfToday, calendar: calendar)
        }

        isoFormatter.timeZone = calendar.timeZone
        guard token.count == 10, let parsed = isoFormatter.date(from: token) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    /// The next time this weekday comes round, never today.
    ///
    /// "ship friday" said on a Friday means *next* Friday — a due date already in the past
    /// by the time it is read is worse than one a week out.
    private static func nextOccurrence(
        ofWeekday weekday: Int, after startOfToday: Date, calendar: Calendar
    ) -> Date? {
        let current = calendar.component(.weekday, from: startOfToday)
        var offset = weekday - current
        if offset <= 0 { offset += 7 }
        return calendar.date(byAdding: .day, value: offset, to: startOfToday)
    }

    // MARK: - Bulk splitting

    /// Splits a free-form paragraph into individual task lines.
    ///
    /// Newlines always separate. List markers are stripped. A single unbulleted line is
    /// also split on commas and semicolons, so "call mom, buy milk" is two tasks — but a
    /// line that *was* bulleted is left alone, because its commas are prose.
    static func split(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: .newlines)
        let hadBullet = rawLines.contains { strippedBullet($0) != nil }

        let lines = rawLines
            .map { strippedBullet($0) ?? $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count == 1, !hadBullet, let only = lines.first else { return lines }

        let parts = only
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.count > 1 ? parts : lines
    }

    /// The line without its leading list marker, or `nil` when it had none.
    private static func strippedBullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }

        if "-*•▪◦‣·>#".contains(first) {
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }

        // `1.` / `2)` — a number followed by a separator.
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let separator = afterDigits.first, separator == "." || separator == ")" else {
            return nil
        }
        let rest = afterDigits.dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}
