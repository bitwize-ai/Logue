import Foundation
@testable import Logue
import Testing

@Suite("TaskEdit")
struct TaskEditTests {
    // MARK: - Tag normalisation

    @Test("A plain word is a tag")
    func plainWordIsATag() {
        #expect(TaskEdit.normalisedTag("launch") == "launch")
    }

    @Test("A leading hash is stripped, so typing it either way works")
    func leadingHashIsStripped() {
        #expect(TaskEdit.normalisedTag("#launch") == "launch")
        #expect(TaskEdit.normalisedTag("  #launch  ") == "launch")
    }

    @Test("Tags keep the casing the user typed")
    func casingIsPreserved() {
        #expect(TaskEdit.normalisedTag("Launch") == "Launch")
    }

    @Test("Hyphens and underscores are allowed, other punctuation is not")
    func charsetIsEnforced() {
        #expect(TaskEdit.normalisedTag("q3-launch") == "q3-launch")
        #expect(TaskEdit.normalisedTag("q3_launch") == "q3_launch")
        #expect(TaskEdit.normalisedTag("launch!") == nil)
        #expect(TaskEdit.normalisedTag("two words") == nil)
    }

    @Test("An empty or hash-only tag is rejected rather than silently added")
    func emptyTagIsRejected() {
        #expect(TaskEdit.normalisedTag("") == nil)
        #expect(TaskEdit.normalisedTag("#") == nil)
        #expect(TaskEdit.normalisedTag("   ") == nil)
    }

    @Test("A tag is truncated to the parser's limit")
    func tagIsTruncated() {
        let long = String(repeating: "a", count: TaskTextParser.maxTagLength + 20)
        #expect(TaskEdit.normalisedTag(long)?.count == TaskTextParser.maxTagLength)
    }

    // MARK: - Adding tags

    @Test("Adding a tag appends it")
    func addingAppends() {
        #expect(TaskEdit.addingTag("launch", to: ["work"]) == ["work", "launch"])
    }

    @Test("Adding a duplicate is a no-op regardless of casing")
    func addingDuplicateIsNoOp() {
        #expect(TaskEdit.addingTag("Work", to: ["work"]) == ["work"])
        #expect(TaskEdit.addingTag("work", to: ["work"]) == ["work"])
    }

    @Test("Adding an invalid tag leaves the list alone")
    func addingInvalidIsNoOp() {
        #expect(TaskEdit.addingTag("two words", to: ["work"]) == ["work"])
    }

    @Test("The parser's tag ceiling is respected")
    func tagCeilingIsRespected() {
        let full = (0 ..< TaskTextParser.maxTags).map { "tag\($0)" }
        #expect(TaskEdit.addingTag("extra", to: full) == full)
    }

    // MARK: - Removing tags

    @Test("Removing a tag is case-insensitive")
    func removingIsCaseInsensitive() {
        #expect(TaskEdit.removingTag("WORK", from: ["work", "launch"]) == ["launch"])
    }

    @Test("Removing a tag that is not there changes nothing")
    func removingMissingIsNoOp() {
        #expect(TaskEdit.removingTag("nope", from: ["work"]) == ["work"])
    }

    // MARK: - Renaming

    @Test("Renaming routes through the same sanitiser capture uses")
    func renameIsSanitised() {
        let task = TaskItem(title: "Old")
        let renamed = TaskEdit.renamed(task, to: "  New title\u{0}  ")
        #expect(renamed.title == "New title")
    }

    @Test("Renaming to nothing falls back rather than producing an empty title")
    func renameToEmptyFallsBack() {
        let task = TaskItem(title: "Old")
        #expect(TaskEdit.renamed(task, to: "   ").title == "Untitled task")
    }

    @Test("A renamed title is bounded, because it reaches a filename")
    func renameIsBounded() {
        let task = TaskItem(title: "Old")
        let long = String(repeating: "x", count: TaskItem.maxTitleLength + 50)
        #expect(TaskEdit.renamed(task, to: long).title.count == TaskItem.maxTitleLength)
    }

    // MARK: - A renamed task still produces a safe filename

    /// Renaming rewrites the `.md` file's name, so a title that escapes the folder would
    /// write outside it. `sanitisedTitle` deliberately does not strip separators — the path
    /// boundary is `DocumentFilename` — so this asserts the two compose.
    @Test("A renamed task cannot escape its folder through the filename")
    func renamedTitleStaysInsideTheFolder() {
        let task = TaskItem(title: "Old")
        for hostile in ["../../etc/passwd", "a/b/c", "/absolute", "with:colons"] {
            let renamed = TaskEdit.renamed(task, to: hostile)
            let filename = TaskFile.filename(for: renamed)
            #expect(!filename.contains("/"))
            #expect(!filename.contains(".."))
            #expect(filename.hasSuffix(".md"))
        }
    }

    @Test("Renaming preserves everything else about the task")
    func renamePreservesTheRest() {
        let source = UUID()
        let task = TaskItem(
            title: "Old", priority: .high, tags: ["work"], sourceMeetingID: source, notes: "keep me"
        )
        let renamed = TaskEdit.renamed(task, to: "New")
        #expect(renamed.id == task.id)
        #expect(renamed.priority == .high)
        #expect(renamed.tags == ["work"])
        #expect(renamed.sourceMeetingID == source)
        #expect(renamed.notes == "keep me")
    }
}
