import Foundation
import SwiftUI

// MARK: - Welcome Meeting Seed Data

extension MeetingStore {
    static func makeWelcomeMeeting() -> MeetingNote {
        let speakers = makeWelcomeSpeakers()
        let segments = makeWelcomeSegments()
        let speakerSegments = makeWelcomeSpeakerSegments(segments: segments)
        let actionItems = makeWelcomeActionItems()
        let bookmarks = makeWelcomeBookmarks()
        let smartMinutes = makeWelcomeSmartMinutes(actionItems: actionItems)

        let summary = "The team walked through Logue's key features including real-time "
            + "transcription, speaker diarization, bookmarks, AI-generated summaries, "
            + "and organization tools. All processing stays on-device for privacy. "
            + "Follow-up scheduled to explore writing features."

        return MeetingNote(
            title: "Getting Started with Logue",
            duration: 110,
            segments: segments,
            actionItems: actionItems,
            summary: summary,
            smartMinutes: smartMinutes,
            recordingMode: .inPerson,
            tags: ["getting-started", "demo"],
            template: .general,
            bookmarks: bookmarks,
            topicKeywords: ["transcription", "speaker diarization", "bookmarks", "AI summary", "privacy"],
            hasSpeakerData: true,
            speakers: speakers,
            speakerSegments: speakerSegments
        )
    }

    // MARK: - Speakers

    private static let speaker1ID = "speaker-alice"
    private static let speaker2ID = "speaker-bob"
    private static let speaker3ID = "speaker-carol"

    private static func makeWelcomeSpeakers() -> [Speaker] {
        [
            Speaker(id: speaker1ID, name: "Alice", color: AppThemeConstants.speakerBlurple),
            Speaker(id: speaker2ID, name: "Bob", color: AppThemeConstants.speakerGreen),
            Speaker(id: speaker3ID, name: "Carol", color: AppThemeConstants.speakerOrange),
        ]
    }

    // MARK: - Transcript Segments

    private static func makeWelcomeSegments() -> [TranscriptSegment] {
        [
            TranscriptSegment(
                text: "Welcome everyone! Let's kick off our first meeting in Logue. "
                    + "I wanted to walk through some of the features.",
                startTime: 0, endTime: 12, speakerLabel: "Alice"
            ),
            TranscriptSegment(
                text: "Sounds great. I've been looking forward to trying the transcription. "
                    + "The speaker detection is really nice.",
                startTime: 12, endTime: 22, speakerLabel: "Bob"
            ),
            TranscriptSegment(
                text: "Yes, and I love that everything stays on-device. No audio is sent to "
                    + "the cloud, which is important for our team's privacy.",
                startTime: 22, endTime: 34, speakerLabel: "Carol"
            ),
            TranscriptSegment(
                text: "Exactly. So the key features to highlight: real-time transcription, "
                    + "speaker diarization, bookmarks during recording, and AI-generated summaries.",
                startTime: 34, endTime: 48, speakerLabel: "Alice"
            ),
            TranscriptSegment(
                text: "I also noticed we can add action items with due dates and reminders. "
                    + "That's going to be useful for follow-ups.",
                startTime: 48, endTime: 58, speakerLabel: "Bob"
            ),
            TranscriptSegment(
                text: "The smart minutes feature is impressive too. It breaks down key decisions, "
                    + "discussion points, and action items automatically.",
                startTime: 58, endTime: 70, speakerLabel: "Carol"
            ),
            TranscriptSegment(
                text: "Let me bookmark this moment. You can add bookmarks at any point during "
                    + "a recording to mark important moments.",
                startTime: 70, endTime: 80, speakerLabel: "Alice"
            ),
            TranscriptSegment(
                text: "One more thing — you can organize meetings into folders and tag them "
                    + "for easy filtering. Really helps when you have lots of meetings.",
                startTime: 80, endTime: 94, speakerLabel: "Bob"
            ),
            TranscriptSegment(
                text: "Great overview. I think we should schedule a follow-up next week "
                    + "to discuss the writing assistant features as well.",
                startTime: 94, endTime: 105, speakerLabel: "Carol"
            ),
            TranscriptSegment(
                text: "Agreed. Let's wrap up. Thanks everyone!",
                startTime: 105, endTime: 110, speakerLabel: "Alice"
            ),
        ]
    }

    // MARK: - Speaker Segments

    // Bug-5: Add bounds guard to prevent crash if segment count changes
    private static func makeWelcomeSpeakerSegments(segments: [TranscriptSegment]) -> [SpeakerSegment] {
        guard segments.count >= 10 else { return [] }
        return [
            SpeakerSegment(speakerId: speaker1ID, startTime: 0, endTime: 12, text: segments[0].text),
            SpeakerSegment(speakerId: speaker2ID, startTime: 12, endTime: 22, text: segments[1].text),
            SpeakerSegment(speakerId: speaker3ID, startTime: 22, endTime: 34, text: segments[2].text),
            SpeakerSegment(speakerId: speaker1ID, startTime: 34, endTime: 48, text: segments[3].text),
            SpeakerSegment(speakerId: speaker2ID, startTime: 48, endTime: 58, text: segments[4].text),
            SpeakerSegment(speakerId: speaker3ID, startTime: 58, endTime: 70, text: segments[5].text),
            SpeakerSegment(speakerId: speaker1ID, startTime: 70, endTime: 80, text: segments[6].text),
            SpeakerSegment(speakerId: speaker2ID, startTime: 80, endTime: 94, text: segments[7].text),
            SpeakerSegment(speakerId: speaker3ID, startTime: 94, endTime: 105, text: segments[8].text),
            SpeakerSegment(speakerId: speaker1ID, startTime: 105, endTime: 110, text: segments[9].text),
        ]
    }

    // MARK: - Action Items & Bookmarks

    private static func makeWelcomeActionItems() -> [ActionItem] {
        [
            ActionItem(
                title: "Explore the AI summary and smart minutes features",
                assignee: "Bob",
                dueDescription: "This week"
            ),
            ActionItem(
                title: "Schedule follow-up meeting to discuss the writing assistant",
                assignee: "Carol",
                dueDescription: "Next Monday"
            ),
            ActionItem(
                title: "Try organizing meetings into folders and adding tags",
                assignee: "Alice",
                dueDescription: "This week"
            ),
        ]
    }

    private static func makeWelcomeBookmarks() -> [Bookmark] {
        [
            Bookmark(label: "Feature overview starts", timestamp: 34, color: .blue),
            Bookmark(label: "Bookmarks demo", timestamp: 70, color: .orange),
            Bookmark(label: "Wrap up & next steps", timestamp: 94, color: .purple),
        ]
    }

    // MARK: - Smart Minutes

    private static func makeWelcomeSmartMinutes(actionItems: [ActionItem]) -> SmartMinutes {
        SmartMinutes(
            keyDecisions: [
                "Adopt Logue as the team's meeting notes tool",
                "Schedule a follow-up to explore writing assistant features",
            ],
            discussionPoints: [
                "Real-time transcription with speaker identification",
                "On-device processing ensures complete privacy",
                "Bookmarks can be placed during recording to mark key moments",
                "AI-generated smart minutes automate note-taking",
                "Folder and tag organization for managing many meetings",
            ],
            actionItems: actionItems.map(\.title),
            followUps: [
                "Review the writing assistant and document analysis features",
                "Explore calendar integration for upcoming meetings",
            ],
            attendeeSummary: [
                AttendeeContribution(
                    name: "Alice",
                    keyPoints: ["Led the feature walkthrough", "Demonstrated bookmarks"],
                    speakingTimePercent: 40
                ),
                AttendeeContribution(
                    name: "Bob",
                    keyPoints: ["Highlighted action items and organization features"],
                    speakingTimePercent: 30
                ),
                AttendeeContribution(
                    name: "Carol",
                    keyPoints: ["Emphasized privacy benefits and smart minutes"],
                    speakingTimePercent: 30
                ),
            ]
        )
    }
}
