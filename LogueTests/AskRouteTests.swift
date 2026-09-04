import Foundation
import Testing

@testable import Logue

/// Pins the routing matrix that used to live inside `AgentChatView`.
///
/// The cases below are the behaviour as it shipped, not a new design: the Deep
/// Research branch from the input bar's `onSend` and the ImagePlayground branch from
/// `sendMessage`, including the attachment suppression. If one of these fails after a
/// change to `AskRouter`, the change altered what a send does — not just where the
/// decision lives.
@Suite("AskRouter")
struct AskRouteTests {
    // MARK: - Nothing to send

    @Test("An empty prompt with no attachments is not a send")
    func emptyPromptDoesNotSend() {
        #expect(AskRouter.route(for: .init(text: "")) == nil)
    }

    @Test("A prompt of only whitespace is not a send")
    func whitespaceOnlyDoesNotSend() {
        #expect(AskRouter.route(for: .init(text: "   \n\t  ")) == nil)
    }

    @Test("An attachment with no prompt is a send")
    func attachmentAloneSends() {
        // Dropping a file and asking nothing is how you say "read this".
        #expect(AskRouter.route(for: .init(text: "", hasAttachments: true)) == .agentLoop)
    }

    @Test("Emptiness is judged after trimming, even with the Deep Research chip lit")
    func whitespaceWithDeepResearchDoesNotSend() {
        // The chip must not turn an empty box into a research run.
        let request = AskRouter.Request(text: "  ", deepResearchRequested: true)
        #expect(AskRouter.route(for: request) == nil)
    }

    @Test("Emptiness outranks a firing image classifier")
    func whitespaceWithImageIntentDoesNotSend() {
        let request = AskRouter.Request(text: " ", imageIntentFires: true)
        #expect(AskRouter.route(for: request) == nil)
    }

    // MARK: - The ordinary path

    @Test("An ordinary question runs the agent loop")
    func ordinaryQuestionUsesAgentLoop() {
        #expect(AskRouter.route(for: .init(text: "what did I miss today?")) == .agentLoop)
    }

    // MARK: - Deep Research

    @Test("The Deep Research chip routes to Deep Research")
    func deepResearchChipRoutes() {
        let request = AskRouter.Request(text: "compare these vendors", deepResearchRequested: true)
        #expect(AskRouter.route(for: request) == .deepResearch)
    }

    @Test("Deep Research outranks a firing image classifier")
    func deepResearchBeatsImageIntent() {
        // An explicit request from the user beats an inferred one — the classifier
        // is a guess, the chip is not.
        let request = AskRouter.Request(
            text: "draw a picture of a sunset",
            deepResearchRequested: true,
            imageIntentFires: true
        )
        #expect(AskRouter.route(for: request) == .deepResearch)
    }

    @Test("Deep Research still routes when files are attached")
    func deepResearchWithAttachments() {
        let request = AskRouter.Request(
            text: "research this",
            hasAttachments: true,
            deepResearchRequested: true
        )
        #expect(AskRouter.route(for: request) == .deepResearch)
    }

    // MARK: - ImagePlayground

    @Test("A firing image classifier routes to ImagePlayground with the prompt as concept")
    func imageIntentRoutes() {
        let request = AskRouter.Request(text: "draw a red bicycle", imageIntentFires: true)
        #expect(AskRouter.route(for: request) == .imagePlayground(concept: "draw a red bicycle"))
    }

    @Test("The concept is trimmed")
    func imageConceptIsTrimmed() {
        let request = AskRouter.Request(text: "  draw a red bicycle \n", imageIntentFires: true)
        #expect(AskRouter.route(for: request) == .imagePlayground(concept: "draw a red bicycle"))
    }

    @Test("An attachment suppresses image routing")
    func attachmentSuppressesImageIntent() {
        // "Draw me a diagram of this" alongside a dropped document means read the
        // document, not invent a picture.
        let request = AskRouter.Request(
            text: "draw a diagram of this",
            hasAttachments: true,
            imageIntentFires: true
        )
        #expect(AskRouter.route(for: request) == .agentLoop)
    }

    @Test("A quiet classifier leaves an image-sounding prompt on the agent loop")
    func imageIntentOffStaysOnAgentLoop() {
        // Routing disabled in Settings, or the score under threshold, both arrive
        // here as `imageIntentFires: false`.
        let request = AskRouter.Request(text: "draw a red bicycle", imageIntentFires: false)
        #expect(AskRouter.route(for: request) == .agentLoop)
    }

    // MARK: - Surface independence

    @Test("The route does not depend on which window asked", arguments: AskSurface.allCases)
    func routeIsIndependentOfSurface(surface: AskSurface) {
        // The invariant issue #61 exists to establish: the same question gets the
        // same pipeline from the main window and from the island. `AskSurface` is
        // deliberately not an input to `route`, and this test is what stops someone
        // adding it later.
        _ = surface
        let request = AskRouter.Request(text: "summarise my last meeting")
        #expect(AskRouter.route(for: request) == .agentLoop)
    }

    // MARK: - Deep Research needs a question

    @Test("The Deep Research chip alone is not a question")
    func deepResearchNeedsText() {
        // A send carrying only attachments is valid, so it passes the empty check — and
        // routing that to Deep Research appended an empty user bubble and ran the whole
        // seven-step pipeline on "". The files are handed back either way, because research
        // takes no attachments on either surface.
        let route = AskRouter.route(
            for: AskRouter.Request(text: "   ", hasAttachments: true, deepResearchRequested: true)
        )
        #expect(route == .agentLoop)
    }

    @Test("Deep Research with a question still routes to Deep Research")
    func deepResearchWithTextIsUnchanged() {
        let route = AskRouter.route(
            for: AskRouter.Request(text: "compare A and B", deepResearchRequested: true)
        )
        #expect(route == .deepResearch)
    }

    @Test("Deep Research with a question and attachments still routes to Deep Research")
    func deepResearchWithTextAndFiles() {
        let route = AskRouter.route(
            for: AskRouter.Request(
                text: "compare these",
                hasAttachments: true,
                deepResearchRequested: true
            )
        )
        #expect(route == .deepResearch)
    }
}
