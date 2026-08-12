import Foundation
import os.log

/// Everything about a session in progress that cannot be recovered from the audio files alone.
///
/// The audio is written continuously, so a crash leaves most of it on disk. What it does not leave
/// is any record of *where each stretch of it belongs* — the placements are only resolved when
/// recording stops — or the transcript, which is appended in memory with `persistImmediately:
/// false`. Without those, the recovered files are two recordings of unknown offset and the meeting
/// has no text at all.
struct RecordingCheckpoint: Codable, Equatable {
    let meetingID: UUID
    let sessionStart: Date
    let timeOffset: TimeInterval
    let segments: [TranscriptSegment]
    let micPlacements: [CaptureSegmentTimeline.Placement]
    let systemPlacements: [CaptureSegmentTimeline.Placement]
    /// File names rather than URLs. The containing directory is derived from the meeting identifier,
    /// and an absolute path written down before a container migration would point at nothing.
    let micFileName: String?
    let systemFileName: String?
    let writtenAt: Date

    private static let fileName = "checkpoint.json"
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "RecordingCheckpoint")

    /// How much of the session this checkpoint can speak for: the furthest point any placement
    /// reaches.
    ///
    /// The post-recording pass is bounded by this, so a recovery cannot claim more of the meeting
    /// than it actually holds — which is what stops a truncated recovery deleting correct transcript.
    var coveredDuration: TimeInterval {
        let ends = (micPlacements + systemPlacements).map { $0.sessionStart + $0.duration }
        return ends.max() ?? 0
    }

    static func write(_ checkpoint: RecordingCheckpoint) throws {
        let directory = try InProgressRecordingStore.directory(for: checkpoint.meetingID)
        let url = directory.appending(component: fileName)
        let data = try JSONEncoder().encode(checkpoint)
        // Atomic, because the alternative to a whole checkpoint is the previous whole one, never
        // half of this one.
        try data.write(to: url, options: .atomic)
    }

    static func read(meetingID: UUID) -> RecordingCheckpoint? {
        do {
            let directory = try InProgressRecordingStore.directory(for: meetingID)
            let url = directory.appending(component: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RecordingCheckpoint.self, from: data)
        } catch {
            logger.error("Could not read checkpoint: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
