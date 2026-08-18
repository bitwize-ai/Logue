import Foundation

/// Whether the transcriber should be hearing the microphone right now.
///
/// Voice activity decides what the *transcriber* is given, and nothing else. The file on disk and
/// the diarization timeline receive every buffer regardless of what this says — the saved audio is
/// the meeting's record, and the diarizer needs the silence to place what follows it. A
/// voice-activity model that is wrong should cost a wrong word, not a hole in the meeting.
///
/// Withholding silence is not merely cheaper. Measured against `SpeechAnalyzer`, two utterances
/// separated by eight seconds of silence transcribed *better* with the silence withheld than with
/// it streamed: the continuous run rendered "The quarterly numbers came in higher" as "that ours
/// came in higher". Silence is not context the model needs.
struct TranscriptionGate {
    enum State: Equatable {
        case closed
        case open
        /// Speech has ended, but the tail has not run out yet.
        case closing(since: TimeInterval)
    }

    /// How long the gate stays open past the end of speech, so trailing consonants survive.
    let tail: TimeInterval

    private(set) var state: State = .closed

    var isOpen: Bool {
        state != .closed
    }

    mutating func speechStarted() {
        state = .open
    }

    /// Speech ended. Only meaningful while the gate is open — a stray end event with no start
    /// behind it must not put a closed gate into its tail, which would open it.
    mutating func speechEnded(at time: TimeInterval) {
        guard state == .open else { return }
        state = .closing(since: time)
    }

    /// Moves time forward, closing the gate once the tail has run out.
    mutating func advance(to now: TimeInterval) {
        guard case let .closing(since) = state else { return }
        if now - since >= tail {
            state = .closed
        }
    }

    mutating func reset() {
        state = .closed
    }
}
