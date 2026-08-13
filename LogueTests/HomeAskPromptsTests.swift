import Foundation
@testable import Logue
import Testing

/// What a card says when the user asks about it. These sentences are the only
/// place a user-authored title crosses into an LLM message, so the guard worth
/// keeping is that a title can decorate the sentence but never restructure it.
@Suite("HomeAskPrompts")
struct HomeAskPromptsTests {
    // MARK: - Sanitization

    @Test("Newlines are stripped so a title cannot restructure the message")
    func newlinesAreStripped() {
        let sanitized = HomeAskPrompts.sanitize("Q3\nReview\r\nNorthwind", fallback: "x")
        #expect(!sanitized.contains("\n"))
        #expect(!sanitized.contains("\r"))
        #expect(sanitized == "Q3ReviewNorthwind")
    }

    @Test("Control characters are stripped")
    func controlCharactersAreStripped() {
        let sanitized = HomeAskPrompts.sanitize("Q3\u{0}Rev\u{7}iew", fallback: "x")
        #expect(sanitized == "Q3Review")
    }

    @Test("Titles are truncated to the maximum length")
    func titlesAreTruncated() {
        let long = String(repeating: "a", count: 400)
        #expect(HomeAskPrompts.sanitize(long, fallback: "x").count == HomeAskPrompts.maxTitleLength)
    }

    @Test("An empty or whitespace-only title falls back")
    func emptyTitlesFallBack() {
        #expect(HomeAskPrompts.sanitize("", fallback: "Untitled meeting") == "Untitled meeting")
        #expect(HomeAskPrompts.sanitize("   \n  ", fallback: "Untitled meeting") == "Untitled meeting")
    }

    // MARK: - The sentences

    @Test("An unsummarized meeting asks for a summary; a summarized one does not")
    func meetingVariantsDiffer() {
        let fresh = HomeAskPrompts.meeting(title: "Q3 Review", isSummarized: false)
        let done = HomeAskPrompts.meeting(title: "Q3 Review", isSummarized: true)
        #expect(fresh != done)
        #expect(fresh.contains("Summarize"))
        #expect(done.contains("decisions"))
        #expect(fresh.contains("Q3 Review"))
        #expect(done.contains("Q3 Review"))
    }

    @Test("Every prompt quotes the sanitized title, never the raw one")
    func promptsQuoteTheSanitizedTitle() {
        let raw = "Draft\nmemo"
        for prompt in [
            HomeAskPrompts.meeting(title: raw, isSummarized: false),
            HomeAskPrompts.document(title: raw),
            HomeAskPrompts.actionItem(title: raw),
            HomeAskPrompts.calendarEvent(title: raw),
        ] {
            #expect(prompt.contains("Draftmemo"))
            #expect(!prompt.contains("\n"))
        }
    }

    @Test("Each object type gets its own verb")
    func eachTypeHasItsOwnVerb() {
        #expect(HomeAskPrompts.document(title: "Memo").contains("continue writing"))
        #expect(HomeAskPrompts.actionItem(title: "Send pricing").contains("What do I need to do"))
        #expect(HomeAskPrompts.calendarEvent(title: "Design sync").contains("Prepare me for"))
    }

    @Test("A blank title of each kind names its kind")
    func blankTitlesNameTheirKind() {
        #expect(HomeAskPrompts.meeting(title: "", isSummarized: false).contains("Untitled meeting"))
        #expect(HomeAskPrompts.document(title: "").contains("Untitled document"))
    }
}
