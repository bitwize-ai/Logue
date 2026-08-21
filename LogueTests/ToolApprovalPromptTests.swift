import Foundation
import Testing

@testable import Logue

/// What an approval card says is about to happen, and to what.
///
/// The card answered this with five hand-written sentences and a fallback of "Agent wants to
/// run <toolName>". None named the thing being acted on — and every destructive tool takes a
/// UUID, so "Agent wants to delete a document" was the whole of what the user was told before
/// being asked for Touch ID.
@Suite("ToolApprovalPrompt")
struct ToolApprovalPromptTests {
    private func json(_ pairs: [String: String]) -> String {
        let body = pairs.keys.sorted()
            .map { "\"\($0)\": \"\(pairs[$0] ?? "")\"" }
            .joined(separator: ", ")
        return "{\(body)}"
    }

    private func sentence(
        _ tool: String,
        _ arguments: [String: String],
        resolving name: String? = nil
    ) -> String {
        ToolApprovalPrompt.sentence(
            toolNamed: tool,
            arguments: json(arguments),
            resolve: { _ in name }
        )
    }

    // MARK: - Coverage

    @Test("Every tool that can ask for approval has something to say")
    @MainActor
    func everyGatedToolHasAPrompt() {
        // Walks the real registry rather than a list kept in step by hand, so adding a
        // destructive tool without a sentence is a red build rather than a card reading
        // "Run delete_everything" over a Touch ID button.
        let gated = AgentCoordinator.allKnownTools().filter { $0.clearance != .regular }
        #expect(gated.isEmpty == false, "if this is empty the walk found nothing and proves nothing")

        let missing = gated.map(\.name).filter { !ToolApprovalPrompt.knows(toolNamed: $0) }
        #expect(missing.isEmpty, "no approval prompt for: \(missing.sorted())")
    }

    // MARK: - Naming the target

    @Test("A document is named, not referred to by its id")
    func documentIsNamed() {
        let id = UUID().uuidString
        let result = sentence("delete_document", ["documentID": id], resolving: "Q3 Planning")
        #expect(result == "Delete “Q3 Planning”")
        #expect(result.contains(id) == false)
    }

    @Test("Deleting a space says what else goes with it")
    func spaceDeletionSaysWhatItTakes() {
        // delete_space trashes every document and meeting inside it and its children. A
        // sentence reading "Delete “Work”" describes a fraction of what the button does.
        let result = sentence("delete_space", ["spaceID": UUID().uuidString], resolving: "Work")
        #expect(result == "Delete, with everything in it, “Work”")
    }

    @Test("A target carried as a literal is used as written")
    func literalTargetsAreUsed() {
        #expect(sentence("write_text_to_file", ["path": "~/notes/todo.md"]) == "Write to “~/notes/todo.md”")
        #expect(sentence("draft_email", ["to": "sam@example.com"]) == "Draft an email to “sam@example.com”")
        #expect(sentence("web_search", ["query": "swift actors"]) == "Search the web for “swift actors”")
    }

    // MARK: - When the name is not available

    @Test("An unresolvable id leaves the action alone rather than showing a UUID")
    func unresolvedTargetShowsNoID() {
        // The document is gone, or the model invented the id. A UUID on the card tells the
        // user nothing and reads as a bug at the exact moment they are deciding whether to
        // trust the agent.
        let id = UUID().uuidString
        let result = sentence("delete_document", ["documentID": id], resolving: nil)
        #expect(result == "Delete")
        #expect(result.contains(id) == false)
    }

    @Test("A malformed id is not shown either")
    func malformedIDIsNotShown() {
        let result = sentence("delete_document", ["documentID": "not-a-uuid"], resolving: "Should not appear")
        #expect(result == "Delete")
    }

    @Test("A missing argument leaves the action alone")
    func missingArgumentIsSafe() {
        #expect(sentence("delete_document", [:], resolving: "Nope") == "Delete")
        #expect(sentence("write_text_to_file", [:]) == "Write to")
    }

    @Test("An unknown tool still says it wants to run")
    func unknownToolIsHonest() {
        // It is still asking for permission, so say so plainly rather than inventing a
        // description of something there is no rule for.
        #expect(sentence("some_future_tool", [:]) == "Run some_future_tool")
    }

    // MARK: - Targets are user-authored text

    @Test("A multi-line title becomes one line")
    func targetsAreFlattened() {
        // A document title is whatever the user typed, and a newline in it would split the
        // sentence in half and leave the verb sitting alone above Approve.
        let result = sentence("delete_document", ["documentID": UUID().uuidString], resolving: "Draft\n\nPart two")
        #expect(result == "Delete “Draft Part two”")
    }

    @Test("A very long target is cut")
    func targetsAreBounded() {
        let long = String(repeating: "n", count: 400)
        let result = sentence("delete_document", ["documentID": UUID().uuidString], resolving: long)
        #expect(result.count < long.count)
        #expect(result.contains("…"))
    }

    // MARK: - References

    @Test("The reference names which store to ask")
    func referenceCarriesItsKind() {
        let id = UUID()
        let document = ToolApprovalPrompt.reference(
            toolNamed: "delete_document",
            arguments: json(["documentID": id.uuidString])
        )
        #expect(document == ToolApprovalPrompt.Reference(kind: .document, id: id))

        let space = ToolApprovalPrompt.reference(
            toolNamed: "rename_space",
            arguments: json(["spaceID": id.uuidString, "newName": "Archive"])
        )
        #expect(space?.kind == .space)
    }

    @Test("A tool whose target is a literal has no reference to resolve")
    func literalToolsHaveNoReference() {
        #expect(ToolApprovalPrompt.reference(toolNamed: "web_search", arguments: json(["query": "x"])) == nil)
    }
}
