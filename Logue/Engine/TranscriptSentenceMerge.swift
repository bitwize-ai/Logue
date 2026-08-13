import Foundation

/// Whether a newly finalised line continues the one before it.
///
/// The live transcriber finalises when it is confident, not when a sentence ends, so a single
/// thought arrives as "The agent helps assemble" followed by "it into something you can judge".
/// Read back later that is jarring, and it is the reason the transcript looks broken however the
/// blocks are drawn — the lines themselves are cut in the wrong places.
///
/// Joining them as they arrive fixes it at the source: the stored transcript is made of sentences,
/// so the live view and everything derived from it agree.
enum TranscriptSentenceMerge {
    /// Longest a merged line may run before it is left alone. Someone who never pauses for breath
    /// should still not end up with one line for the whole meeting.
    static let maximumDuration: TimeInterval = 30

    /// Longest silence a sentence may span. Past this the speaker stopped, whatever the punctuation.
    static let maximumGap: TimeInterval = 2

    static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ".!?…".contains(last)
    }

    /// Whether `next` should be folded into `previous`.
    static func shouldMerge(previous: TranscriptSegment, next: TranscriptSegment) -> Bool {
        // Never merge across speakers: a reply is a new line however it is punctuated.
        guard previous.speakerLabel == next.speakerLabel else { return false }
        guard !endsSentence(previous.text) else { return false }
        guard next.startTime - previous.endTime <= maximumGap else { return false }
        guard next.endTime - previous.startTime <= maximumDuration else { return false }
        return true
    }

    /// `previous` extended to cover `next`, keeping its identity and start.
    static func merged(_ previous: TranscriptSegment, with next: TranscriptSegment) -> TranscriptSegment {
        var joined = previous
        let left = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        joined.text = [left, right].filter { !$0.isEmpty }.joined(separator: " ")
        joined.endTime = max(previous.endTime, next.endTime)
        return joined
    }
}
