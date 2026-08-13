import Foundation

/// What the transcript prints in its left-hand column beside each line.
///
/// A mark is printed when the clock has moved on or the speaker has changed, so a turn always
/// announces itself and a long turn is still broken up by time. Lines in between carry no mark,
/// which is what lets a run of sentences read as one paragraph.
///
/// Kept apart from the view because it decides what a reader sees, and that is worth testing: the
/// rule is the whole reason identifying speakers no longer re-cuts the transcript.
enum TranscriptGutter {
    struct Mark: Equatable {
        let time: String
        let speaker: String?
        let shortSpeaker: String
    }

    /// How far the meeting must move on before the gutter prints another time.
    static let defaultInterval: TimeInterval = 10

    static func marks(
        for segments: [TranscriptSegment],
        interval: TimeInterval = defaultInterval
    ) -> [UUID: Mark] {
        var marks: [UUID: Mark] = [:]
        var lastStampedAt: TimeInterval?
        var previousSpeaker: String?
        var hasPrevious = false

        for segment in segments {
            let isFirst = lastStampedAt == nil
            let advanced = (segment.startTime - (lastStampedAt ?? 0)) >= interval
            let speakerChanged = hasPrevious && previousSpeaker != segment.speakerLabel

            previousSpeaker = segment.speakerLabel
            hasPrevious = true

            guard isFirst || advanced || speakerChanged else { continue }

            marks[segment.id] = Mark(
                time: TranscriptSegment.formatTime(segment.startTime),
                speaker: segment.speakerLabel,
                shortSpeaker: segment.speakerLabel.map(SpeakerShortLabel.forSpeaker) ?? ""
            )
            lastStampedAt = segment.startTime
        }
        return marks
    }
}
