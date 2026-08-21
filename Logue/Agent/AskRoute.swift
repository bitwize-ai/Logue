import Foundation

/// Which window a question was asked from.
///
/// Carried alongside a send so per-conversation state can be attributed to the
/// surface that started it. It deliberately says nothing about *how* the question
/// is answered — that is `AskRoute`'s job, and the whole point of issue #61 is that
/// the answer does not depend on which window you asked from.
enum AskSurface: String, Codable, Sendable, CaseIterable {
    /// The Ask Logue surface in the main window.
    case mainWindow
    /// The Command Center island, floating over another app.
    case island
}

/// Where one send goes.
///
/// Three pipelines can answer a question and they are mutually exclusive. Modelled
/// as an enum rather than a pair of booleans so "Deep Research *and* an image
/// prompt" cannot be represented — with flags that state is reachable and the
/// caller has to remember which one wins.
enum AskRoute: Equatable, Sendable {
    /// The normal agent loop: `AgentCoordinator` with the tool registry.
    case agentLoop
    /// `DeepResearchCoordinator`'s multi-step pipeline.
    case deepResearch
    /// Apple's ImagePlayground sheet, seeded with the prompt.
    case imagePlayground(concept: String)
}

/// The one place that decides which pipeline answers a question.
///
/// Before this existed the decision was split across two spots inside
/// `AgentChatView` — the Deep Research branch in the input bar's `onSend`, and the
/// ImagePlayground branch at the top of `sendMessage`. Being inside a `View` made it
/// unreachable from the Command Center island, which is why the island had no
/// routing at all and sent every question straight to a bare completion.
///
/// Kept free of SwiftUI, `UserDefaults` and the classifier itself so the matrix is
/// testable without a view or a model: the caller resolves its own inputs and this
/// only answers the question. `imageIntentFires` is passed in rather than read from
/// `PromptIntentClassifier` because that call also consults a settings toggle, and a
/// decision that reads global state is a decision you cannot write a test for.
enum AskRouter {
    /// Everything the decision depends on.
    struct Request: Equatable, Sendable {
        /// The prompt as typed, before trimming.
        var text: String
        /// Whether the send carries files. Attachments suppress image routing:
        /// someone who dropped a document in and typed "draw me a diagram of this"
        /// wants the agent to read the file, not ImagePlayground to invent a picture.
        var hasAttachments: Bool
        /// The Deep Research chip was lit for this send.
        var deepResearchRequested: Bool
        /// The intent classifier scored this prompt as an image request, with
        /// routing enabled in Settings.
        var imageIntentFires: Bool

        init(
            text: String,
            hasAttachments: Bool = false,
            deepResearchRequested: Bool = false,
            imageIntentFires: Bool = false
        ) {
            self.text = text
            self.hasAttachments = hasAttachments
            self.deepResearchRequested = deepResearchRequested
            self.imageIntentFires = imageIntentFires
        }
    }

    /// The route for this send, or `nil` when there is nothing to send.
    ///
    /// Returning `nil` rather than a `.none` case keeps "empty" from being a
    /// pipeline the callers have to remember to ignore.
    ///
    /// Precedence, highest first:
    /// 1. **Nothing to send.** Empty prompt and no attachments.
    /// 2. **Deep Research**, when the chip is lit. An explicit request from the user
    ///    outranks an inferred one — the classifier is a guess, the chip is not.
    /// 3. **ImagePlayground**, when the classifier fires and nothing is attached.
    /// 4. **The agent loop**, which is what everything else is.
    static func route(for request: Request) -> AskRoute? {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // An attachment on its own is a valid send: drop a file, ask nothing, and
        // the agent is expected to read it.
        guard !trimmed.isEmpty || request.hasAttachments else { return nil }

        if request.deepResearchRequested {
            return .deepResearch
        }

        if request.imageIntentFires, !request.hasAttachments {
            return .imagePlayground(concept: trimmed)
        }

        return .agentLoop
    }
}
