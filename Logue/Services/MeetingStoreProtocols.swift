import Foundation

// MARK: - MeetingStore Protocol Facades

// These protocols decompose MeetingStore's 50+ method API into focused, testable surfaces.
// MeetingStore conforms to all of them. Tests and new code can depend on narrow protocols
// instead of the full MeetingStore, improving testability and API clarity.

/// Core CRUD operations for meetings.
@MainActor
protocol MeetingRepository: AnyObject {
    var meetings: [MeetingNote] { get set }
    var selectedMeetingID: UUID? { get set }
    var isLoaded: Bool { get }

    func createMeeting(
        title: String,
        mode: RecordingMode,
        template: MeetingTemplate,
        inSpace spaceID: UUID?
    ) -> MeetingNote
    func createVoiceNote(inSpace spaceID: UUID?) -> MeetingNote
    func updateMeeting(_ meeting: MeetingNote)
    func deleteMeeting(id: UUID)
    func trashMeeting(id: UUID)
    func restoreMeeting(id: UUID)
    func permanentlyDeleteMeeting(id: UUID)
    func emptyMeetingTrash()
    func renameMeeting(id: UUID, newTitle: String)
    func togglePin(id: UUID)
    func toggleArchive(id: UUID)
    func saveMeeting(id: UUID)
}

/// Transcript segment management during and after recording.
@MainActor
protocol MeetingSegmentManager: AnyObject {
    func appendSegment(_ segment: TranscriptSegment, to meetingID: UUID, persistImmediately: Bool)
    func mergeMicSegments(_ micSegments: [TranscriptSegment], into meetingID: UUID)
    func updateSegmentText(meetingID: UUID, segmentID: UUID, text: String)
    func updateDuration(_ duration: TimeInterval, for meetingID: UUID)
}

/// Speaker diarization data management.
@MainActor
protocol MeetingSpeakerManager: AnyObject {
    func updateSpeakerData(for meetingID: UUID, speakers: [Speaker], speakerSegments: [SpeakerSegment])
}

/// AI-generated content (summaries, titles, action items).
@MainActor
protocol MeetingAIContentManager: AnyObject {
    func setSummary(_ summary: String, for meetingID: UUID)
    func setSmartMinutes(_ minutes: SmartMinutes, for meetingID: UUID)
    func setActionItems(_ items: [ActionItem], for meetingID: UUID)
    func generateAITitle(for meetingID: UUID) async
    func generateAISummary(for meetingID: UUID) async -> SummaryGenerationResult
    func suggestSpace(for meetingID: UUID) async -> UUID?
}

/// Bookmark and tag management.
@MainActor
protocol MeetingMetadataManager: AnyObject {
    func addBookmark(_ bookmark: Bookmark, to meetingID: UUID)
    func removeBookmark(bookmarkID: UUID, from meetingID: UUID)
    func updateBookmark(_ bookmark: Bookmark, in meetingID: UUID)
    func addTag(_ tag: String, to meetingID: UUID)
    func removeTag(_ tag: String, from meetingID: UUID)
    func setTopicKeywords(_ keywords: [String], for meetingID: UUID)
    var allTags: [String] { get }
}

/// Search and discovery.
@MainActor
protocol MeetingSearchable: AnyObject {
    func searchMeetings(query: String) async -> [MeetingNote]
    func searchWithSnippets(query: String) -> [(meeting: MeetingNote, matchType: String, snippet: String)]
    func relatedMeetings(to meetingID: UUID, limit: Int) -> [MeetingNote]
}

/// Space (folder) organization.
@MainActor
protocol MeetingSpaceOrganizer: AnyObject {
    func meetings(inSpace spaceID: UUID) -> [MeetingNote]
    func moveMeeting(id: UUID, toSpace spaceID: UUID?)
    func unfileMeetings(inSpace spaceID: UUID)
    func trashMeetings(inSpace spaceID: UUID)
}
