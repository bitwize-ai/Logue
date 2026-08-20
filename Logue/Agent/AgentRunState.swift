import Foundation

/// The live state of one agent run, and which conversation it belongs to.
///
/// `AgentCoordinator` is a singleton, and its `isProcessing` / `isStreaming` /
/// `streamingText` / `activeToolCalls` are global flags. With one surface that was
/// harmless — there was only ever one thread on screen. With two, it is not: a run
/// started from the Command Center island sets the same flags the main window's
/// conversation reads, so the island's spinner, its streaming text and its tool
/// cards all paint onto whatever thread the main window happens to be showing.
///
/// This is that state with an owner attached. Every read is scoped to a
/// conversation and answers for the idle state when the run belongs to a different
/// one, so a surface can only ever see its own activity.
///
/// Pure and free of `@Observable`, actors and the engine, so the scoping rule is
/// testable without a model — one of the ground rules on issue #56.
struct AgentRunState {
    /// The conversation the current — or most recent — run belongs to.
    ///
    /// Deliberately survives `finish()`: `lastError` outlives the run so the banner
    /// can persist until acknowledged, and an error with no owner would paint on
    /// every surface. Cleared on the next `begin`.
    private(set) var conversationID: UUID?

    private(set) var isProcessing = false
    private(set) var isStreaming = false
    private(set) var streamingText = ""
    private(set) var activeToolCalls: [AgentToolCall] = []
    private(set) var lastError: String?

    init() {}

    // MARK: - Transitions

    /// Starts a run and takes ownership for `conversationID`.
    ///
    /// Clears the previous run's error: the existing coordinator drops `lastError`
    /// at the top of every `send`, and a stale error surviving into an unrelated
    /// run would be attributed to the wrong turn.
    mutating func begin(conversationID: UUID) {
        self.conversationID = conversationID
        isProcessing = true
        isStreaming = false
        streamingText = ""
        activeToolCalls = []
        lastError = nil
    }

    mutating func beginStreaming() {
        isStreaming = true
        streamingText = ""
    }

    mutating func appendToken(_ token: String) {
        streamingText += token
    }

    mutating func resetStreamingText() {
        streamingText = ""
    }

    mutating func setActiveToolCalls(_ calls: [AgentToolCall]) {
        activeToolCalls = calls
    }

    mutating func fail(_ message: String) {
        lastError = message
    }

    mutating func dismissError() {
        lastError = nil
    }

    /// Ends the run. Keeps `conversationID` and `lastError` so the owning surface
    /// can still show a banner for a run that has finished.
    mutating func finish() {
        isProcessing = false
        isStreaming = false
        streamingText = ""
        activeToolCalls = []
    }

    // MARK: - Scoped reads

    /// Whether the live run, if any, belongs to this conversation.
    func owns(_ conversationID: UUID) -> Bool {
        self.conversationID == conversationID
    }

    func isProcessing(for conversationID: UUID) -> Bool {
        owns(conversationID) && isProcessing
    }

    func isStreaming(for conversationID: UUID) -> Bool {
        owns(conversationID) && isStreaming
    }

    func streamingText(for conversationID: UUID) -> String {
        owns(conversationID) ? streamingText : ""
    }

    func activeToolCalls(for conversationID: UUID) -> [AgentToolCall] {
        owns(conversationID) ? activeToolCalls : []
    }

    func lastError(for conversationID: UUID) -> String? {
        owns(conversationID) ? lastError : nil
    }
}
