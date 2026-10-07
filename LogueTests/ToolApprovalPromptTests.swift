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

    // MARK: - A target cannot lie about itself

    @Test("A title cannot reverse the sentence it is shown in")
    func targetCannotSpoofWithBidi() {
        // The card sits above a Touch ID prompt. A title carrying U+202E — which can arrive
        // in a .md file dropped into the markdown folder, or from a create_document call a
        // prompt-injected model made — would otherwise render the filename backwards, so the
        // card names a different document than the one about to be deleted.
        let id = UUID().uuidString
        let result = sentence("delete_document", ["documentID": id], resolving: "report\u{202E}gnp.txt")
        #expect(result.unicodeScalars.contains { $0.value == 0x202E } == false)
        #expect(result == "Delete \u{201C}reportgnp.txt\u{201D}")
    }

    @Test("A literal argument is stripped too, not only a resolved name")
    func literalTargetIsStripped() {
        // `write_text_to_file` takes the path straight from the model's arguments — there is
        // no store lookup to launder it, so this is the shorter path to the same card.
        let result = sentence("write_text_to_file", ["path": "~/notes\u{202E}dm.txt"], resolving: nil)
        #expect(result.unicodeScalars.contains { $0.value == 0x202E } == false)
    }

    @Test("A newline in a target cannot split the sentence")
    func targetStaysOnOneLine() {
        let id = UUID().uuidString
        let result = sentence("delete_document", ["documentID": id], resolving: "Q3\nPlanning")
        #expect(result.contains("\n") == false)
        #expect(result == "Delete \u{201C}Q3 Planning\u{201D}")
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
        #expect(result == "Delete a document")
        #expect(result.contains(id) == false)
    }

    @Test("A malformed id is not shown either")
    func malformedIDIsNotShown() {
        let result = sentence("delete_document", ["documentID": "not-a-uuid"], resolving: "Should not appear")
        #expect(result == "Delete a document")
    }

    @Test("A missing argument leaves the action alone")
    func missingArgumentIsSafe() {
        #expect(sentence("delete_document", [:], resolving: "Nope") == "Delete a document")
        #expect(sentence("write_text_to_file", [:]) == "Write to a file")
    }

    @Test("A sentence with no name still says what kind of thing")
    func unnamedTargetsAreNeverABareVerb() {
        // Reminders and calendar events are never resolved, so this is what their cards
        // always say. They read "Delete" and "Change" — the same as each other, and less
        // than the "run delete_reminder" they replaced — above a Touch ID prompt.
        let id = UUID().uuidString
        #expect(sentence("delete_reminder", ["reminderID": id]) == "Delete a reminder")
        #expect(sentence("update_reminder", ["reminderID": id]) == "Change a reminder")
        #expect(sentence("delete_calendar_event", ["eventID": id]) == "Delete a calendar event")
        #expect(sentence("update_calendar_event", ["eventID": id]) == "Change a calendar event")
        #expect(sentence("delete_space", ["spaceID": id]) == "Delete a space, with everything in it")
    }

    @Test("A sentence missing its argument is still a whole sentence")
    func missingLiteralsAreWholeSentences() {
        // Each of these leads into its target — "Write to", "Draft an email to" — and would
        // stop mid-phrase without one.
        #expect(sentence("list_directory", [:]) == "List a folder")
        #expect(sentence("read_file_at_path", [:]) == "Read a file")
        #expect(sentence("delete_file_at_path", [:]) == "Delete a file")
        #expect(sentence("draft_email", [:]) == "Draft an email")
        #expect(sentence("web_search", [:]) == "Search the web")
        #expect(sentence("fetch_web_page", [:]) == "Open a web page")
        #expect(sentence("rename_space", [:]) == "Rename a space")
        #expect(sentence("move_document", [:]) == "Move a document")
    }

    @Test("Arguments that are not a readable object leave the sentence whole")
    func unreadableArgumentsAreSafe() {
        let resolve: (ToolApprovalPrompt.Reference) -> String? = { _ in "Nope" }
        for arguments in ["not json", "[1, 2]", "", #"{"path": null}"#] {
            let shown = ToolApprovalPrompt.sentence(toolNamed: "delete_file_at_path", arguments: arguments, resolve: resolve)
            #expect(shown == "Delete a file", "arguments: \(arguments)")
        }
    }

    @Test("Tools with nothing to name say what they read")
    func targetlessToolsAreStated() {
        #expect(sentence("get_location", [:]) == "Read your current location")
        #expect(sentence("fetch_contacts", [:]) == "Read your contacts")
        #expect(sentence("fetch_contacts", ["name": "Sam"]) == "Read your contacts matching “Sam”")
    }

    // MARK: - Where the end is the part that matters

    @Test("A long path keeps its filename")
    func longPathKeepsTheFile() {
        // Cut from the tail, every file in a deep folder produced the same sentence — the
        // folders, and never the name of the file about to be deleted.
        let folder = "/Volumes/Archive/Documents/Projects/Client Work/2026/Invoices/Final/"
        let march = sentence("delete_file_at_path", ["path": folder + "invoice-march.pdf"])
        let april = sentence("delete_file_at_path", ["path": folder + "invoice-april.pdf"])
        #expect(march.hasSuffix("invoice-march.pdf”"))
        #expect(march != april)
        #expect(march.hasPrefix("Delete the file “/Volumes/"))
    }

    @Test("A web address shows its real host")
    func webAddressShowsTheHost() {
        // The host says where the request goes. Padding in front of it, or a trusted name
        // in the user-info position, must not be what the card ends up showing.
        let padded = "https://accounts.example.com." + String(repeating: "a", count: 60) + ".elsewhere.tld/login"
        let shown = sentence("fetch_web_page", ["url": padded])
        #expect(shown.hasSuffix(".elsewhere.tld…”"), "the host's end, and a mark that a path follows")
        #expect(shown.contains("accounts.example.com") == false)

        let disguised = sentence("fetch_web_page", ["url": "https://trusted.example@elsewhere.tld/login"])
        #expect(disguised == "Open “elsewhere.tld/login”")
        #expect(disguised.contains("trusted.example") == false)

        #expect(sentence("fetch_web_page", ["url": "https://example.com/docs/guide"]) == "Open “example.com/docs/guide”")
        #expect(sentence("fetch_web_page", ["url": "https://example.com/"]) == "Open “example.com”")
        #expect(sentence("fetch_web_page", ["url": "https://example.com:8443/x"]) == "Open “example.com:8443/x”")
    }

    @Test("An address with no host is shown as written, bounded")
    func hostlessAddressFallsBack() {
        #expect(sentence("fetch_web_page", ["url": "example.com/docs"]) == "Open “example.com/docs”")
        let long = "file:///" + String(repeating: "d/", count: 60) + "secrets.txt"
        let shown = sentence("fetch_web_page", ["url": long])
        #expect(shown.hasSuffix("secrets.txt”"))
        #expect(shown.count <= ToolApprovalPrompt.maxTargetLength + "Open “”".count)
    }

    @Test("A look-alike host is shown as what will be requested")
    func punycodeHostIsNotDecoded() {
        // xn--pple-43d.com decodes to a name whose first letter is Cyrillic and which reads
        // as a well-known one. The request goes to the encoded form, so that is what is shown.
        let shown = sentence("fetch_web_page", ["url": "https://xn--pple-43d.com/login"])
        #expect(shown == "Open “xn--pple-43d.com/login”")
    }

    @Test("A percent-encoded control cannot get past the scrub")
    func encodedControlsStayEncoded() {
        // Decoding the path after scrubbing would bring a bidi override or a newline back.
        let reversed = sentence("fetch_web_page", ["url": "https://example.com/%E2%80%AEmoc.elgoog"])
        #expect(reversed.unicodeScalars.contains { $0.value == 0x202E } == false)
        let split = sentence("fetch_web_page", ["url": "https://example.com/%0A%0AApproved"])
        #expect(split.contains("\n") == false)
    }

    @Test("A percent-encoded host is shown as the host that will be reached")
    func encodedHostIsResolved() {
        // The connection resolves the escapes, so `%2E` is a dot and the registrable domain
        // is whatever follows it. Shown still encoded, the real destination sat behind hex.
        let hidden = sentence("fetch_web_page", ["url": "https://good.example%2Eelsewhere.tld/x"])
        #expect(hidden == "Open “good.example.elsewhere.tld/x”")
        #expect(sentence("fetch_web_page", ["url": "https://%65lsewhere.tld/"]) == "Open “elsewhere.tld”")
    }

    @Test("An escaped delimiter in the host is not resolved into one")
    func encodedHostDelimitersStayEncoded() {
        // Resolved, `%2F` would end the host on the card while the request's host runs on.
        for escape in ["%2F", "%3F", "%23", "%3A", "%20", "%40", "%00", "%E2%80%AE"] {
            let shown = sentence("fetch_web_page", ["url": "https://trusted.example\(escape)x.elsewhere.tld/p"])
            #expect(shown == "Open “trusted.example\(escape)x.elsewhere.tld/p”", "escape \(escape)")
        }
    }

    @Test("Only an escaped hostname character is resolved")
    func onlyHostnameCharactersAreResolved() {
        // Decided per escape: the hidden dot is revealed, the slash beside it is not.
        #expect(sentence("fetch_web_page", ["url": "https://a%2Eb%2Fc.tld/p"]) == "Open “a.b%2Fc.tld/p”")
        // A delimiter with a combining mark after it is one grapheme that is not "/", which
        // is how a list of characters to refuse lets a real slash through.
        let combined = sentence("fetch_web_page", ["url": "https://trusted.example%2F%EF%B8%8Fx.elsewhere.tld/p"])
        #expect(combined == "Open “trusted.example%2F%EF%B8%8Fx.elsewhere.tld/p”")
        // A Cyrillic letter spelled as an escape is the same look-alike punycode spells.
        #expect(sentence("fetch_web_page", ["url": "https://%D0%B0pple.com/login"]) == "Open “%D0%B0pple.com/login”")
        // Look-alikes for a slash and a dot, the card's own closing quote, a blank filler.
        for escape in ["%E2%81%84", "%EF%BC%8E", "%E2%80%9D", "%E3%85%A4", "%5B", "%3D"] {
            let shown = sentence("fetch_web_page", ["url": "https://trusted.example\(escape)x.elsewhere.tld/p"])
            #expect(shown == "Open “trusted.example\(escape)x.elsewhere.tld/p”", "escape \(escape)")
        }
    }

    @Test("Trailing whitespace is part of what is sent")
    func trailingWhitespaceIsShown() {
        // The tool is handed the argument whole, so the card must not parse a tidier one.
        #expect(sentence("fetch_web_page", ["url": "https://example.com/x "]) == "Open “example.com/x%20”")
    }

    @Test("A query is marked even when the host takes the whole line")
    func queryIsMarkedBesideALongHost() {
        for length in 55 ... 70 {
            let host = String(repeating: "h", count: length) + ".tld"
            let shown = sentence("fetch_web_page", ["url": "https://\(host)/p?q=1"])
            #expect(shown.contains("?"), "host of \(host.count) hid the query: \(shown)")
            #expect(shown.contains(".tld"), "host of \(host.count) lost its end")
            #expect(shown.count <= ToolApprovalPrompt.maxTargetLength + "Open “”".count)
        }
    }

    @Test("The fetch refuses an address that carries credentials")
    func fetchRefusesEmbeddedCredentials() async {
        // The card names the host without them, so they must never be sent: an address
        // with user-info is how data would leave under a card that showed none.
        // The refusal itself, not any failure: a network error is an `AgentToolError` too,
        // and a test satisfied by one would pass with the guard gone — having sent them.
        for address in ["https://data:secret@example.com/", "https://data@example.com/", "https://@example.com/"] {
            await #expect {
                _ = try await FetchWebPageTool().execute(arguments: ["url": address])
            } throws: { error in
                guard case AgentToolError.invalidParameter("url", _) = error else { return false }
                return true
            }
        }
    }

    @Test("A long path cannot push the query off the card")
    func queryKeepsItsShare() {
        let shown = sentence(
            "fetch_web_page",
            ["url": "https://example.com/" + String(repeating: "a", count: 80) + "?secret=1"]
        )
        #expect(shown.contains("?secret=1"))
        #expect(shown.hasPrefix("Open “example.com/aaa"))
    }

    @Test("What is sent is what is shown, even when it would not display")
    func invisibleQueryCharactersAreShownEncoded() {
        // Scrubbed before parsing, an invisible character vanished from the card while the
        // request still carried it, percent-encoded: a query that read as empty, and was not.
        let bell = "\\u0007"
        let shown = sentence("fetch_web_page", ["url": "https://example.com/?q=\(bell)a"])
        #expect(shown == "Open “example.com?q=%07a”")
    }

    @Test("The query is not dropped")
    func queryIsShown() {
        // It is where a request carries data out. Cut it if it is long, but never hide it.
        #expect(sentence("fetch_web_page", ["url": "https://example.com/c?d=notes"]) == "Open “example.com/c?d=notes”")
        #expect(sentence("fetch_web_page", ["url": "https://example.com?x=1"]) == "Open “example.com?x=1”")
        let long = "https://example.com/c?d=" + String(repeating: "z", count: 200)
        let shown = sentence("fetch_web_page", ["url": long])
        #expect(shown.hasPrefix("Open “example.com/c?d=zzz"))
        #expect(shown.hasSuffix("…”"))
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
