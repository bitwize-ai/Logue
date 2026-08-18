import Foundation
@testable import Logue
import Testing

@Suite("TaskTextParser")
struct TaskTextParserTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// A fixed Wednesday, so "friday" and "next week" are reproducible.
    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 12
        return calendar.date(from: components) ?? .distantPast
    }

    private func parse(_ text: String) -> ParsedTask {
        TaskTextParser.parse(text, now: now, calendar: calendar)
    }

    private func day(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    // MARK: - Title

    @Test("Plain text becomes the title untouched")
    func plainTitle() {
        #expect(parse("Send the deck").title == "Send the deck")
    }

    @Test("Blank input falls back rather than producing an unnamed task")
    func blankFallsBack() {
        #expect(parse("   ").title.isEmpty == false)
        #expect(parse("#tag !").title.isEmpty == false)
    }

    @Test("An over-long title is truncated")
    func longTitleTruncated() {
        let parsed = parse(String(repeating: "a", count: 500))
        #expect(parsed.title.count <= TaskItem.maxTitleLength)
    }

    @Test("Control characters are stripped from the title")
    func controlCharactersStripped() {
        #expect(parse("Send\u{0}the deck").title == "Sendthe deck")
    }

    // MARK: - Tags

    @Test("A hash token becomes a tag and leaves the title")
    func tagExtracted() {
        let parsed = parse("Send the deck #launch")
        #expect(parsed.tags == ["launch"])
        #expect(parsed.title == "Send the deck")
    }

    @Test("Several tags are all captured")
    func severalTags() {
        #expect(parse("Ship #launch #urgent").tags == ["launch", "urgent"])
    }

    @Test("A repeated tag is stored once, ignoring case")
    func duplicateTagsCollapse() {
        #expect(parse("Ship #Launch #launch").tags == ["Launch"])
    }

    @Test("A bare hash is not a tag")
    func bareHashIgnored() {
        let parsed = parse("Fix issue # 42")
        #expect(parsed.tags.isEmpty)
    }

    @Test("Tag count is capped so a pasted wall of hashes cannot flood a task")
    func tagsCapped() {
        let parsed = parse("Ship #a #b #c #d #e #f #g #h")
        #expect(parsed.tags.count <= TaskTextParser.maxTags)
    }

    // MARK: - Priority

    @Test("A trailing bang means high priority")
    func bangIsHigh() {
        #expect(parse("Ship it !").priority == .high)
        #expect(parse("Ship it !!").priority == .high)
        #expect(parse("Ship it !!!").priority == .high)
    }

    @Test("The bang is removed from the title")
    func bangStripped() {
        #expect(parse("Ship it !!").title == "Ship it")
    }

    @Test("Priority defaults to medium")
    func defaultPriority() {
        #expect(parse("Ship it").priority == .medium)
    }

    @Test("A bang inside a sentence is punctuation, not priority")
    func innerBangIgnored() {
        let parsed = parse("Ship it! Then rest")
        #expect(parsed.priority == .medium)
        #expect(parsed.title == "Ship it! Then rest")
    }

    // MARK: - Due dates

    @Test("Today and tomorrow resolve against the supplied clock")
    func relativeDays() {
        #expect(day(parse("Ship today").dueDate) == "2026-08-12")
        #expect(day(parse("Ship tomorrow").dueDate) == "2026-08-13")
    }

    @Test("Next week is seven days out")
    func nextWeek() {
        #expect(day(parse("Ship next week").dueDate) == "2026-08-19")
    }

    @Test("An explicit ISO date is taken as written")
    func isoDate() {
        #expect(day(parse("Ship 2026-09-01").dueDate) == "2026-09-01")
    }

    @Test("A weekday resolves to its next occurrence, never today")
    func weekday() {
        // 2026-08-12 is a Wednesday.
        #expect(day(parse("Ship friday").dueDate) == "2026-08-14")
        #expect(day(parse("Ship wednesday").dueDate) == "2026-08-19")
    }

    @Test("An in-N-days phrase resolves and is removed")
    func inDays() {
        let parsed = parse("Ship in 3 days")
        #expect(day(parsed.dueDate) == "2026-08-15")
        #expect(parsed.title == "Ship")
    }

    @Test("An absurd day count is clamped rather than overflowing the calendar")
    func inDaysClamped() {
        #expect(parse("Ship in 99999 days").dueDate != nil)
    }

    @Test("No date phrase means no due date")
    func noDate() {
        #expect(parse("Ship the thing").dueDate == nil)
    }

    // MARK: - Recurrence

    @Test("Every-week is a recurrence, not a due date")
    func everyWeek() {
        let parsed = parse("Water the plants every week")
        #expect(parsed.recurrence == TaskRecurrence(unit: .week, interval: 1))
        #expect(parsed.title == "Water the plants")
    }

    @Test("An interval recurrence is understood")
    func everyNWeeks() {
        #expect(parse("Invoice every 2 weeks").recurrence == TaskRecurrence(unit: .week, interval: 2))
    }

    @Test("Single-word recurrences are understood")
    func wordRecurrence() {
        #expect(parse("Standup daily").recurrence == TaskRecurrence(unit: .day, interval: 1))
    }

    @Test("Next week is a due date, not a recurrence")
    func nextWeekIsNotRecurrence() {
        #expect(parse("Ship next week").recurrence == nil)
    }

    // MARK: - Everything at once

    @Test("A full line is decomposed completely")
    func fullLine() {
        let parsed = parse("Send the revised deck to Priya tomorrow #launch !!")
        #expect(parsed.title == "Send the revised deck to Priya")
        #expect(parsed.priority == .high)
        #expect(day(parsed.dueDate) == "2026-08-13")
        #expect(parsed.tags == ["launch"])
    }

    // MARK: - Non-ASCII

    @Test("Emoji and CJK survive parsing intact")
    func multiByteSurvives() {
        let parsed = parse("送出簡報 📊 tomorrow #発表 !")
        #expect(parsed.title == "送出簡報 📊")
        #expect(parsed.tags == ["発表"])
        #expect(parsed.priority == .high)
        #expect(day(parsed.dueDate) == "2026-08-13")
    }

    // MARK: - Bulk splitting

    @Test("Newlines separate tasks")
    func splitOnNewlines() {
        #expect(TaskTextParser.split("call mom\nbuy milk") == ["call mom", "buy milk"])
    }

    @Test("List markers are stripped")
    func splitStripsBullets() {
        let lines = TaskTextParser.split("- call mom\n* buy milk\n1. email Sarah")
        #expect(lines == ["call mom", "buy milk", "email Sarah"])
    }

    @Test("A single unbulleted line splits on commas and semicolons")
    func splitSingleLine() {
        let lines = TaskTextParser.split("call mom, buy milk; email Sarah")
        #expect(lines == ["call mom", "buy milk", "email Sarah"])
    }

    @Test("A single line with no separators stays one task")
    func splitKeepsOneLine() {
        #expect(TaskTextParser.split("call mom") == ["call mom"])
    }

    @Test("A bulleted line is not further split on its commas")
    func splitDoesNotOverReach() {
        #expect(TaskTextParser.split("- call mom, then dad") == ["call mom, then dad"])
    }

    @Test("Blank lines are discarded")
    func splitDropsBlanks() {
        #expect(TaskTextParser.split("call mom\n\n\nbuy milk") == ["call mom", "buy milk"])
    }
}
