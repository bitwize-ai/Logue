import Foundation

/// Decides which batch-transcribed segments survive a second opinion from voice activity detection.
///
/// The transcriber and the voice-activity model can disagree, and when they do the transcriber is
/// usually the one worth believing: it produced words, which is positive evidence, where the VAD
/// produced an absence, which is not. The filter exists because a transcriber asked to describe
/// silence will occasionally invent a sentence — but that is a narrow problem, and paying for it by
/// deleting real speech is a bad trade.
///
/// So a segment is dropped only when the VAD found speech *somewhere* and none of it here, and only
/// while the disagreement stays small. A VAD that wants to delete half the meeting has not found
/// hallucinations; it has failed to hear something — quiet speech far from the microphone, a voice
/// under noise suppression — and its opinion is discarded whole.
enum BatchTranscriptFilter {
    struct SpeechRegion: Equatable {
        let startTime: TimeInterval
        let endTime: TimeInterval

        init(startTime: TimeInterval, endTime: TimeInterval) {
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    /// What happened, so the caller can log it without recomputing.
    struct Result {
        let segments: [TranscriptSegment]
        let removed: Int
        /// True when the VAD wanted to remove so much that it was disregarded entirely.
        let distrustedVAD: Bool
    }

    static func filter(_ segments: [TranscriptSegment], speechRegions: [SpeechRegion]) -> Result {
        guard !segments.isEmpty, !speechRegions.isEmpty else {
            return Result(segments: segments, removed: 0, distrustedVAD: false)
        }

        let kept = segments.filter { segment in
            speechRegions.contains { region in
                region.endTime > segment.startTime && region.startTime < segment.endTime
            }
        }

        // Nothing survived: the VAD and the transcriber agree on nothing at all, which says more
        // about the VAD than the transcript.
        guard !kept.isEmpty else {
            return Result(segments: segments, removed: 0, distrustedVAD: true)
        }

        // A minority surviving is the same failure in a quieter form. Half is the line: below it,
        // this is no longer a few hallucinated lines being trimmed, it is speech going missing.
        guard kept.count * 2 >= segments.count else {
            return Result(segments: segments, removed: 0, distrustedVAD: true)
        }

        return Result(segments: kept, removed: segments.count - kept.count, distrustedVAD: false)
    }
}
