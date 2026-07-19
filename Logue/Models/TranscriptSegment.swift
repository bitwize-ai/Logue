import Foundation

/// Identifies the audio source that produced a transcript segment.
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
