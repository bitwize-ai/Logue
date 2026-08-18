import Foundation

/// Why a request to start recording did or did not begin a session.
///
/// A bare `Bool` was not enough, and the gap cost two rounds of defects. Callers need to know
/// *why* a start was refused, because the answer decides whether the request they were holding
/// should wait or be dropped — and reconstructing that reason afterwards, by re-reading
/// `isRecovering` once the moment had passed, both missed reasons and read the wrong one.
enum RecordingStartOutcome: Equatable {
    case started

    /// An interrupted session is being rebuilt. Minutes on a long meeting, then it ends.
    case rebuildingInterruptedSession
    /// The previous session is still being written and composed. Also minutes; also ends.
    case previousSessionStopping
    /// Another start is already in flight.
    case alreadyStarting

    /// The user denied microphone access.
    case microphoneDenied
    /// The speech engine could not be set up.
    case engineUnavailable
    /// Audio capture never reached the recording state.
    case captureFailed

    /// The refusal a given recorder state implies.
    ///
    /// Here rather than in the manager so the mapping is testable, and so the manager's file
    /// stays inside its length budget. Re-deriving this afterwards from `isRecovering` both
    /// missed `.stopping` and read state that had already moved on.
    init(refusedIn state: RecordingSessionManager.RecordingState) {
        self = switch state {
        case .recovering: .rebuildingInterruptedSession
        case .stopping: .previousSessionStopping
        default: .alreadyStarting
        }
    }

    var started: Bool {
        self == .started
    }

    /// Whether the obstacle clears on its own, so a waiting request is worth keeping.
    ///
    /// The distinction the previous version got wrong twice. It treated "being rebuilt" as the
    /// only self-clearing refusal, so a capture that arrived while the last session was still
    /// stopping — a user pressing Stop and immediately clicking their next calendar event — was
    /// dropped in silence. And it treated every other refusal as self-clearing by default,
    /// so a denied microphone left the request armed for the life of the process, ready to
    /// start recording the next time that meeting was merely opened.
    var clearsOnItsOwn: Bool {
        switch self {
        case .rebuildingInterruptedSession, .previousSessionStopping, .alreadyStarting:
            true
        case .started, .microphoneDenied, .engineUnavailable, .captureFailed:
            false
        }
    }
}
