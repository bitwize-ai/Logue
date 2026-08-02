import Foundation
@testable import Logue
import Testing

/// End-to-end check that a recording longer than the in-memory audio timeline is still transcribed
/// and diarized to its final minute.
///
/// Runs the real Parakeet and Sortformer models over a real audio file, so it is opt-in: point
/// `LOGUE_LONG_AUDIO` at the file and `LOGUE_LONG_AUDIO_HOURS` at its length. Without them the
/// suite skips, keeping the normal test run fast and offline.
@Suite("Long recording, end to end", .serialized)
struct LongRecordingE2ETests {
    private var fixture: (url: URL, hours: Double)? {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LOGUE_LONG_AUDIO"],
              let hours = Double(env["LOGUE_LONG_AUDIO_HOURS"] ?? ""),
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return (URL(fileURLWithPath: path), hours)
    }

    @MainActor
    private func makeInitializedDiarizer() async throws -> DiarizationManager {
        let diarizer = DiarizationManager()
        try await diarizer.initialize()
        try #require(diarizer.isStreamingActive, "Sortformer must be streaming for the long-recording pass")
        return diarizer
    }

    @Test(
        "A recording past the in-memory limit is transcribed and diarized to its last minute",
        .enabled(if: {
            let env = ProcessInfo.processInfo.environment
            // Both are needed, so both gate the run — checking only one turns a half-configured
            // environment into a failure where the doc comment promises a skip.
            guard let path = env["LOGUE_LONG_AUDIO"], Double(env["LOGUE_LONG_AUDIO_HOURS"] ?? "") != nil
            else { return false }
            return FileManager.default.fileExists(atPath: path)
        }())
    )
    @MainActor
    func longRecordingIsProcessedToTheEnd() async throws {
        let fixture = try #require(fixture, "LOGUE_LONG_AUDIO / LOGUE_LONG_AUDIO_HOURS must both be set")

        let totalSeconds = fixture.hours * 3600
        let capacitySeconds = Double(
            AudioTimelineMixer.capacity(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
        ) / 16000

        print(String(
            format: "Fixture %.2f h; in-memory timeline holds %.2f h — %@",
            fixture.hours, capacitySeconds / 3600,
            totalSeconds > capacitySeconds ? "the recording does not fit" : "WARNING: it fits, ceiling not exercised"
        ))

        let diarizer = try await makeInitializedDiarizer()

        let started = Date()
        let result = try #require(
            await diarizer.processRecordingFile(fixture.url),
            "the long-recording pass returned nothing"
        )
        let elapsed = Date().timeIntervalSince(started)

        let lastSegmentEnd = result.segments.map(\.endTime).max() ?? 0
        let lastSpeakerEnd = result.speakers.map(\.endTime).max() ?? 0
        let speakerCount = Set(result.speakers.map(\.speakerIndex)).count

        print(String(
            format: """
            Processed %.2f h in %.0f s (%.0fx realtime)
              transcript: %d segments, last ends at %.0f s (%.1f%% of the recording)
              speakers:   %d distinct, %d segments, last ends at %.0f s (%.1f%% of the recording)
            """,
            fixture.hours, elapsed, totalSeconds / max(elapsed, 1),
            result.segments.count, lastSegmentEnd, 100 * lastSegmentEnd / totalSeconds,
            speakerCount, result.speakers.count, lastSpeakerEnd, 100 * lastSpeakerEnd / totalSeconds
        ))

        // The whole point: both passes reach the end of the recording, not the end of what fitted
        // in memory. A minute of slack — the tail of a recording is usually trailing silence, and
        // a fixed allowance stays meaningful whether the fixture runs ten minutes or ten hours.
        let slack: TimeInterval = 60
        #expect(!result.segments.isEmpty)
        #expect(!result.speakers.isEmpty)
        #expect(lastSegmentEnd > totalSeconds - slack, "transcript stops short of the end")
        #expect(lastSpeakerEnd > totalSeconds - slack, "speaker labels stop short of the end")
        #expect(speakerCount >= 2, "two speakers alternate throughout the fixture")

        // Speech is present in every tenth of the recording, so coverage cannot be front-loaded.
        for tenth in 0 ..< 10 {
            let from = totalSeconds * Double(tenth) / 10
            let to = totalSeconds * Double(tenth + 1) / 10
            let hasText = result.segments.contains { $0.startTime >= from && $0.startTime < to }
            #expect(hasText, "no transcript between \(Int(from))s and \(Int(to))s")
        }
    }
}
