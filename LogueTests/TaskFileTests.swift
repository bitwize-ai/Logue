import Foundation
@testable import Logue
import Testing

@Suite("TaskFile")
struct TaskFileTests {
    /// Built in the **local** timezone on purpose.
    ///
    /// A due date is a calendar day in the user's timezone, not an instant: the parser
    /// produces `calendar.startOfDay(for:)` against `.current`, and the file stores
    /// `yyyy-MM-dd`. Storing in UTC instead would be off by one for every positive-offset
    /// timezone — a Tokyo user's "tomorrow" is still today in UTC — so the format layer is
    /// local, and a test that builds UTC midnight and asserts against a UTC calendar is
    /// testing something production never does.
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: iso) ?? .distantPast
    }

    private func sample() -> TaskItem {
        TaskItem(
            id: UUID(uuidString: "3F2A1B4C-5D6E-7F80-9112-233445566778") ?? UUID(),
            title: "Send the revised deck",
            status: .todo,
            priority: .high,
            dueDate: date("2026-08-14"),
            tags: ["launch", "urgent"],
            recurrence: TaskRecurrence(unit: .week, interval: 1),
            completedCount: 2,
            notes: "Split the pricing slide in two."
        )
    }

    // MARK: - Round trip

    @Test("A task round-trips through the file format")
    func roundTrips() throws {
        let task = sample()
        let parsed = try #require(TaskFile.parse(TaskFile.render(task)))
        #expect(parsed.id == task.id)
        #expect(parsed.title == task.title)
        #expect(parsed.status == task.status)
        #expect(parsed.priority == task.priority)
        #expect(parsed.tags == task.tags)
        #expect(parsed.recurrence == task.recurrence)
        #expect(parsed.completedCount == task.completedCount)
        #expect(parsed.notes == task.notes)
    }

    @Test("A due date survives as the same calendar day")
    func dueDateSurvives() throws {
        let parsed = try #require(TaskFile.parse(TaskFile.render(sample())))
        let due = try #require(parsed.dueDate)
        // The invariant is the *day*, in whatever timezone the machine is in — asserting a
        // fixed number here would only pass in one timezone.
        #expect(Calendar.current.isDate(due, inSameDayAs: date("2026-08-14")))
    }

    @Test("A due date is stable across repeated round trips, not drifting a day each time")
    func dueDateDoesNotDrift() throws {
        var task = sample()
        for _ in 0 ..< 3 {
            task = try #require(TaskFile.parse(TaskFile.render(task)))
        }
        let due = try #require(task.dueDate)
        #expect(Calendar.current.isDate(due, inSameDayAs: date("2026-08-14")))
    }

    @Test("Rendering is byte-stable, so an unchanged task produces no git diff")
    func renderingStable() {
        let task = sample()
        #expect(TaskFile.render(task) == TaskFile.render(task))
    }

    @Test("Emoji and CJK survive a round trip")
    func multiByteSurvives() throws {
        var task = sample()
        task.title = "送出簡報 📊"
        task.notes = "確認價格 💰"
        let parsed = try #require(TaskFile.parse(TaskFile.render(task)))
        #expect(parsed.title == "送出簡報 📊")
        #expect(parsed.notes == "確認價格 💰")
    }

    @Test("A title containing a colon survives, because frontmatter quotes it")
    func colonInTitle() throws {
        var task = sample()
        task.title = "Ship: the big one"
        let parsed = try #require(TaskFile.parse(TaskFile.render(task)))
        #expect(parsed.title == "Ship: the big one")
    }

    @Test("A title containing a newline does not break the file")
    func newlineInTitle() throws {
        var task = sample()
        task.title = "Ship\nthe thing"
        let parsed = try #require(TaskFile.parse(TaskFile.render(task)))
        #expect(parsed.title.contains("\n") == false)
        #expect(parsed.id == task.id)
    }

    // MARK: - Tolerant reading

    @Test("A file with no identifier is not a task")
    func missingIdentifierRejected() {
        #expect(TaskFile.parse("---\ntitle: Orphan\n---\nbody") == nil)
    }

    @Test("A malformed identifier is not guessed at")
    func malformedIdentifierRejected() {
        #expect(TaskFile.parse("---\n_logue_task_id: not-a-uuid\ntitle: X\n---\n") == nil)
    }

    @Test("An unknown key is ignored rather than failing the read")
    func unknownKeyIgnored() throws {
        let markdown = """
        ---
        _logue_task_id: 3F2A1B4C-5D6E-7F80-9112-233445566778
        title: Kept
        something_new: 42
        ---
        body
        """
        let parsed = try #require(TaskFile.parse(markdown))
        #expect(parsed.title == "Kept")
    }

    @Test("A malformed status or priority falls back instead of failing the read")
    func malformedEnumsFallBack() throws {
        let markdown = """
        ---
        _logue_task_id: 3F2A1B4C-5D6E-7F80-9112-233445566778
        title: Kept
        status: sideways
        priority: enormous
        ---
        """
        let parsed = try #require(TaskFile.parse(markdown))
        #expect(parsed.status == .todo)
        #expect(parsed.priority == .medium)
    }

    @Test("A malformed due date falls back to no date rather than a wrong one")
    func malformedDueDate() throws {
        let markdown = """
        ---
        _logue_task_id: 3F2A1B4C-5D6E-7F80-9112-233445566778
        title: Kept
        due: sometime
        ---
        """
        let parsed = try #require(TaskFile.parse(markdown))
        #expect(parsed.dueDate == nil)
    }

    @Test("Tags written as a flow sequence are read, because other tools write them that way")
    func flowSequenceTags() throws {
        let markdown = """
        ---
        _logue_task_id: 3F2A1B4C-5D6E-7F80-9112-233445566778
        title: Kept
        tags: [a, b]
        ---
        """
        let parsed = try #require(TaskFile.parse(markdown))
        #expect(parsed.tags == ["a", "b"])
    }

    // MARK: - Filenames

    @Test("A filename is derived from the title and ends in .md")
    func filenameFromTitle() {
        let name = TaskFile.filename(for: sample(), avoiding: [])
        #expect(name.hasSuffix(".md"))
        #expect(name.contains("Send the revised deck"))
    }

    @Test("A filename never contains a path separator, however hostile the title")
    func filenameIsPathSafe() {
        var task = sample()
        task.title = "../../etc/passwd"
        let name = TaskFile.filename(for: task, avoiding: [])
        #expect(name.contains("/") == false)
        #expect(name.hasPrefix(".") == false)
    }

    @Test("A colliding filename is disambiguated")
    func filenameDisambiguates() {
        let task = sample()
        let first = TaskFile.filename(for: task, avoiding: [])
        let second = TaskFile.filename(for: task, avoiding: [first])
        #expect(first != second)
    }

    // MARK: - Folder marker

    @Test("The folder marker carries a readable identifier")
    func markerRoundTrips() throws {
        let id = UUID()
        let contents = TaskFile.folderMarkerContents(id: id)
        #expect(TaskFile.markerIdentifier(in: contents) == id)
    }

    @Test("The marker is recognised by filename")
    func markerRecognised() {
        #expect(TaskFile.isFolderMarker(filename: "_tasks.md"))
        #expect(TaskFile.isFolderMarker(filename: "_TASKS.MD"))
        #expect(TaskFile.isFolderMarker(filename: "tasks.md") == false)
    }
}
