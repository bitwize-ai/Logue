import Foundation

/// Identifies the audio source that produced a transcript segment.
///
/// FluidAudio declares a type of the same name, and the two are not interchangeable. Two things
/// keep them apart, and neither is qualification — the module also declares a `FluidAudio` *struct*,
/// which shadows its own module name, so `FluidAudio.AudioSource` does not compile.
///
/// A bare `AudioSource` resolves to this one, because a module's own declarations beat imported
/// ones. A leading dot resolves against the parameter it is passed to, so `transcribe(source: .system)`
/// is FluidAudio's. Both are what we want; the thing to avoid is assuming a value of one can stand
/// in for the other, since their cases carry different raw values.
enum AudioSource: String, Codable, Sendable, Equatable {
    case system // Remote participants (system audio tap)
    case microphone // Local user (mic)
}

/// A single segment of transcribed speech with timing information.
struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var speakerLabel: String?
    var confidence: Double
    var audioSource: AudioSource?

    init(
        id: UUID = .init(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerLabel: String? = nil,
        confidence: Double = 1.0,
        audioSource: AudioSource? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerLabel = speakerLabel
        self.confidence = confidence
        self.audioSource = audioSource
    }

    var duration: TimeInterval {
        endTime - startTime
    }

    var formattedStartTime: String {
        Self.formatTime(startTime)
    }

    var formattedEndTime: String {
        Self.formatTime(endTime)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
