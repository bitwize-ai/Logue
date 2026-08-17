import Foundation
import os.log

/// Handles the AI pipeline that runs after recording stops:
/// title generation, summary, space suggestion, and linked document creation.
@MainActor
@Observable
final class PostRecordingPipeline {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "PostRecordingPipeline")

    var isGeneratingAISummary = false
    var suggestedSpaceID: UUID?
    var suggestedSpaceMeetingID: UUID?

    private var aiGenerationTask: Task<Void, Never>?
    private var currentAITaskID: UUID?
    /// The meeting the in-flight pass belongs to.
    ///
    /// Kept so `cancel(startingInstead:)` can refuse to take work that is not the caller's.
    /// Starting a recording cancels the previous meeting's pass on purpose — the two compete for
    /// the same model — but recovery starts a pass for the *recovered* meeting and then leaves
    /// `.recovering`, and an automatic capture waiting on exactly that edge cancelled it one
    /// statement later. The recovered meeting kept its default title and never got a summary.
    private var currentMeetingID: UUID?

    // B11: Use [weak self] and only clear state if not cancelled (a new task hasn't replaced us)
    func start(for meetingID: UUID) {
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        isGeneratingAISummary = true
        let taskID = UUID()
        currentAITaskID = taskID
        currentMeetingID = meetingID
        let task = Task { [weak self] in
            defer {
                // Only reset UI state if this is still the active task (not replaced by a newer one)
                if let self, self.currentAITaskID == taskID {
                    self.isGeneratingAISummary = false
                    self.aiGenerationTask = nil
                    self.currentAITaskID = nil
                }
            }
            guard let self else { return }
            let deadline = Date(timeIntervalSinceNow: AppConstants.Diarization.postRecordingTimeoutSeconds)
            await MeetingStore.shared.generateAITitle(for: meetingID)
            guard !Task.isCancelled, Date() < deadline else { return }
            let summaryResult = await MeetingStore.shared.generateAISummary(for: meetingID)
            if case .skipped = summaryResult {
                logger.warning("AI summary skipped — model not loaded")
            } else if case let .failed(error) = summaryResult {
                logger.error("AI summary failed: \(error)")
            }

            guard !Task.isCancelled else { return }
            let autoSaveKey = AppConstants.UserDefaultsKeys.autoSaveSummaryToDocument
            let autoSave = UserDefaults.standard.object(forKey: autoSaveKey) as? Bool ?? true
            if case .success = summaryResult, autoSave {
                autoCreateLinkedDocument(for: meetingID)
            }

            // Smart Highlights — only after summary succeeded, so we don't burn cycles
            // on a meeting that's too short or failed to summarize.
            guard !Task.isCancelled, Date() < deadline else { return }
            if case .success = summaryResult {
                await MeetingStore.shared.generateAIHighlights(for: meetingID)
            }

            guard !Task.isCancelled, Date() < deadline else { return }
            let meeting = MeetingStore.shared.meetings.first { $0.id == meetingID }
            if meeting?.spaceID == nil, !SpaceStore.shared.spaces.isEmpty {
                if let suggested = await MeetingStore.shared.suggestSpace(for: meetingID) {
                    suggestedSpaceID = suggested
                    suggestedSpaceMeetingID = meetingID
                }
            }
        }
        aiGenerationTask = task
    }

    /// Cancels the in-flight pass.
    ///
    /// - Parameter startingInstead: the meeting whose recording is about to begin. A pass
    ///   belonging to a *different* meeting is left alone: it is not competing for the recording
    ///   that is starting, and cancelling it loses that meeting's summary, highlights and linked
    ///   document with nothing to restart them. Pass `nil` to cancel unconditionally.
    func cancel(startingInstead meetingID: UUID? = nil) {
        if let meetingID, let currentMeetingID, currentMeetingID != meetingID {
            return
        }
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        currentAITaskID = nil
        currentMeetingID = nil
        isGeneratingAISummary = false
    }

    // MARK: - Auto-Create Linked Document

    /// Creates a document in the same Space as the meeting, populated with Smart Minutes markdown.
    /// Links it via `summaryDocumentID` for bidirectional navigation.
    private func autoCreateLinkedDocument(for meetingID: UUID) {
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else { return }
        // Only auto-create if meeting is in a space and doesn't already have a linked doc
        guard let spaceID = meeting.spaceID, meeting.summaryDocumentID == nil else { return }

        let markdown = meeting.smartMinutes != nil
            ? meeting.smartMinutesMarkdown()
            : (meeting.summary ?? "")
        guard !markdown.isEmpty else { return }

        let doc = DocumentStore.shared.createDocument(
            title: "\(meeting.title) — Notes",
            body: markdown,
            inSpace: spaceID,
            select: false
        )

        // Link the document to the meeting
        store.moveMeeting(id: meetingID, toSpace: spaceID) // ensure still in space
        if let index = store.meetings.firstIndex(where: { $0.id == meetingID }) {
            store.meetings[index].summaryDocumentID = doc.id
            store.meetings[index].modifiedAt = Date()
            store.saveMeeting(id: meetingID)
        }

        logger.info("Auto-created linked document '\(doc.title, privacy: .private)' for meeting \(meetingID, privacy: .public)")
    }
}
