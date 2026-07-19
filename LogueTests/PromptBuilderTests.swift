@testable import Logue
import Testing

@Suite("PromptBuilder")
struct PromptBuilderTests {
    // MARK: - systemPrompt

    @Test("System prompt mentions the goal mode description")
    func systemPromptContainsGoalMode() {
        for mode in WritingGoalMode.allCases {
            let prompt = PromptBuilder.systemPrompt(for: mode)
            #expect(
                prompt.contains(mode.systemDescription),
                "Expected system prompt to mention goal description for \(mode)"
            )
        }
    }

    @Test("System prompt always requires JSON output")
    func systemPromptRequiresJSON() {
        let prompt = PromptBuilder.systemPrompt(for: .casual)
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("suggestions"))
        #expect(prompt.contains("confidence"))
    }

    // MARK: - userMessage

    @Test("User message includes the full text when under 800 chars")
    func userMessageIncludesShortText() {
        let text = "This are a test sentence."
        let request = TextAnalysisRequest(text: text, cursorOffset: 0, goalMode: .casual)
        let message = PromptBuilder.userMessage(for: request)
        #expect(message.contains(text))
    }

    @Test("User message truncates text longer than 800 chars")
    func userMessageTruncatesLongText() {
        let longText = String(repeating: "Hello world. ", count: 80) // ~1040 chars
        let request = TextAnalysisRequest(text: longText, cursorOffset: 0, goalMode: .casual)
        let message = PromptBuilder.userMessage(for: request)
        #expect(message.count < longText.count + 50, "Message should be shorter than original")
    }

    @Test("User message centres window around cursor for long text")
    func userMessageCentresOnCursor() {
        let prefix = String(repeating: "a ", count: 200)
        let cursor = String(repeating: "CURSOR_TEXT ", count: 5)
        let suffix = String(repeating: "z ", count: 200)
        let text = prefix + cursor + suffix
        let cursorOffset = prefix.count + cursor.count / 2

        let request = TextAnalysisRequest(text: text, cursorOffset: cursorOffset, goalMode: .casual)
        let message = PromptBuilder.userMessage(for: request)
        #expect(message.contains("CURSOR_TEXT"), "Context window should include cursor region")
    }

    // MARK: - messages

    @Test("messages returns system message first, then user message")
    func messagesOrder() {
        let request = TextAnalysisRequest(text: "Hello world", goalMode: .business)
        let msgs = PromptBuilder.messages(for: request)
        #expect(msgs.count == 2)
        #expect(msgs[0].role == .system)
        #expect(msgs[1].role == .user)
    }

    // MARK: - rephrase messages

    @Test("Rephrase messages describe the target style")
    func rephraseMessagesDescribeStyle() {
        let msgs = PromptBuilder.rephraseMessages(text: "hey man wats up", style: .business)
        let systemContent = msgs.first(where: { $0.role == .system })?.content ?? ""
        #expect(systemContent.lowercased().contains("business"))
    }
}
