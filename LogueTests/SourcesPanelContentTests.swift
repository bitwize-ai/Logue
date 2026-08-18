import Foundation
import Testing

@testable import Logue

/// What the sources panel would show, and whether its button appears.
///
/// This type was extracted so the panel and the control that reveals it answer the *same*
/// question — they used to answer two, and a conversation that cited a URL from a tool the
/// button did not recognise had sources it could render and no way to open them. It was the
/// only one of the three helpers extracted in that change with no test, so reverting the fix
/// broke nothing.
@Suite("SourcesPanelContent")
struct SourcesPanelContentTests {
    private func toolResult(_ output: String) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: "",
            toolResult: AgentToolResult(toolCallID: UUID(), output: output)
        )
    }

    private func toolCall(_ name: String, arguments: String = #"{"id":"1"}"#) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(toolName: name, arguments: arguments)]
        )
    }

    // MARK: - The reason this type exists

    @Test("A URL cited by a tool the old heuristic ignored still counts")
    func urlFromAnUnrecognisedToolCounts() {
        // The exact scenario the extraction was for. The button used to ask "is any tool named
        // like a web or library tool?", so a conversation whose only tool was
        // `read_file_at_path` had a panel full of sources and no way to open it.
        let messages = [toolResult("see https://example.com/report for the figures")]

        #expect(SourcesPanelContent.citedURLs(in: messages).count == 1)
        #expect(SourcesPanelContent.hasAnswerSources(in: messages))
        #expect(SourcesPanelContent.hasContent(messages: messages, attachmentCount: 0))
    }

    @Test("A conversation with nothing sourced has nothing to show")
    func nothingSourcedShowsNothing() {
        let messages = [toolResult("no links here"), toolCall("run_javascript", arguments: "")]
        #expect(SourcesPanelContent.hasAnswerSources(in: messages) == false)
        #expect(SourcesPanelContent.hasContent(messages: messages, attachmentCount: 0) == false)
    }

    // MARK: - The panel's question is not the auto-open's

    @Test("A staged attachment is something to draw, but not the agent sourcing an answer")
    func stagedAttachmentIsNotAnAgentSource() {
        // Folding the two together threw the panel open over Home's landing when a file was
        // dropped on the prompt bar, and closed it again on send when the attachment cleared.
        #expect(SourcesPanelContent.hasContent(messages: [], attachmentCount: 1))
        #expect(SourcesPanelContent.hasAnswerSources(in: []) == false)
    }

    // MARK: - URLs

    @Test("Trailing punctuation is trimmed off a cited URL")
    func trailingPunctuationIsTrimmed() {
        let messages = [toolResult("details at https://example.com/report.")]
        #expect(SourcesPanelContent.citedURLs(in: messages).first?.absoluteString
            == "https://example.com/report")
    }

    @Test("The same URL cited twice is listed once")
    func duplicateURLsCollapse() {
        let messages = [
            toolResult("https://example.com/a and https://example.com/a again"),
            toolResult("https://example.com/a in a later turn"),
        ]
        #expect(SourcesPanelContent.citedURLs(in: messages).count == 1)
    }

    @Test("A bare scheme in prose is not offered as a URL")
    func bareSchemesAreIgnored() {
        // The regex settles this one: it requires at least one non-space character after
        // `://`, so this never reaches the host guard. Kept because it is what a tool result
        // discussing protocols actually looks like.
        let messages = [toolResult("read the http:// docs and ftp mirrors")]
        #expect(SourcesPanelContent.citedURLs(in: messages).isEmpty)
    }

    @Test("Something the regex matches but that names no host is not offered as one", arguments: [
        // Parses, `host` is nil.
        "see https:///notes for detail",
        // Parses, `host` is the empty string — the other half of the same guard.
        "see http://:8080/status for detail",
    ])
    func matchesWithoutAHostAreIgnored(text: String) {
        // These reach `guard let host = url.host, !host.isEmpty` and are what makes it earn its
        // place. Delete that guard and this fails; the case that used to stand here did not.
        #expect(SourcesPanelContent.citedURLs(in: [toolResult(text)]).isEmpty)
        #expect(SourcesPanelContent.hasCitedURL(in: [toolResult(text)]) == false)
    }

    @Test("The list of URLs is capped")
    func urlsAreCapped() {
        let many = (1 ... 20).map { "https://example.com/page\($0)" }.joined(separator: " ")
        #expect(SourcesPanelContent.citedURLs(in: [toolResult(many)], limit: 10).count == 10)
    }

    @Test("Only a tool result's output is scanned, not the assistant's prose")
    func proseIsNotScanned() {
        // The panel lists what tools returned. Treating the model's own text as a source would
        // list URLs it invented.
        let message = AgentMessage(role: .assistant, content: "try https://example.com/made-up")
        #expect(SourcesPanelContent.citedURLs(in: [message]).isEmpty)
    }

    // MARK: - References

    @Test("Meeting and document tools are referenced; others are not")
    func referenceToolsAreRecognised() {
        #expect(SourcesPanelContent.isReferenceTool("get_meeting_details"))
        #expect(SourcesPanelContent.isReferenceTool("search_documents"))
        #expect(SourcesPanelContent.isReferenceTool("run_javascript") == false)
    }

    @Test("The same reference twice is listed once, and the list is capped")
    func referencesDedupeAndCap() {
        let repeated = Array(repeating: toolCall("get_meeting_details"), count: 3)
        #expect(SourcesPanelContent.referenceKeys(in: repeated).count == 1)

        let many = (1 ... 12).map { toolCall("get_meeting_details", arguments: #"{"id":"\#($0)"}"#) }
        #expect(SourcesPanelContent.referenceKeys(in: many, limit: 8).count == 8)
    }

    @Test("A reference tool called with no arguments names nothing")
    func emptyArgumentsAreNotAReference() {
        #expect(SourcesPanelContent.referenceKeys(in: [toolCall("list_meetings", arguments: "")]).isEmpty)
    }
}
