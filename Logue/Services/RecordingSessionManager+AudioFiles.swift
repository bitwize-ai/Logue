import AVFoundation
import Foundation

/// Where a finished recording's audio ends up on disk. Extracted from the recording state machine:
/// these are pure file operations with no bearing on the recording lifecycle, and the state machine
/// is long enough without them.
///
/// One rule holds the file together: **the saved file is the meeting's timeline**. A capture source
/// writes only while it is running, so its raw file is shorter than the meeting whenever it joined
/// late or was muted, and laying such a file down as-is plays everything after the gap early. The
/// saved file is therefore composed from each source's placements whenever the raw file would not
/// already line up. Playback depends on that, and so does the long-recording pass, which reads this
/// file back and trusts its timestamps.
extension RecordingSessionManager {
    /// What each capture source recorded and where each stretch of it belongs.
    struct CaptureSources {
        var systemURL: URL?
        var systemPlacements: [CaptureSegmentTimeline.Placement] = []
        var micURL: URL?
        var micPlacements: [CaptureSegmentTimeline.Placement] = []

        var isEmpty: Bool {
            systemURL == nil && micURL == nil
        }

        /// The one source that recorded, with its placements, or nil when both or neither did.
        var soleSource: (url: URL, placements: [CaptureSegmentTimeline.Placement])? {
            switch (systemURL, micURL) {
            case let (url?, nil): (url, systemPlacements)
            case let (nil, url?): (url, micPlacements)
            default: nil
            }
        }

        /// Whether a raw file can be saved as it is, or whether it has to be laid out first.
        ///
        /// Untouched only when a single source ran once from the start of the meeting: then its file
        /// already *is* the timeline. Two sources, a late join or a mute all mean it is not.
        var needsComposing: Bool {
            guard let sole = soleSource else { return !isEmpty }
            return !CaptureSegmentTimeline.fileMatchesSessionTimeline(sole.placements)
        }
    }

    /// What was saved, and whether its timings describe the meeting.
    ///
    /// The distinction is the whole point of returning this rather than letting callers work it out:
    /// the long-recording pass reads this file back and stamps its results over the live transcript,
    /// which is only safe when the file is the meeting's timeline. Working that out after the fact —
    /// from a device clock, or from the file's length — gets it wrong precisely in the cases that
    /// produce a misaligned file, because those are the same cases that disturb the clock.
    enum SavedRecording {
        /// The file is the meeting's timeline. Timings taken from it describe the meeting.
        case onSessionTimeline(URL)
        /// Audio was saved, but laying it out failed, so its timings may not line up.
        case rawFallback(URL)
        /// Nothing was saved.
        case none

        var url: URL? {
            switch self {
            case let .onSessionTimeline(url), let .rawFallback(url): url
            case .none: nil
            }
        }

        /// Whether the post-recording pass may treat this file as the whole session.
        var describesSessionTimeline: Bool {
            if case .onSessionTimeline = self {
                return true
            }
            return false
        }
    }

    // MARK: - Persisting

    /// Saves the session's audio for playback on the meeting's own timeline, and reports whether it
    /// managed to.
    @discardableResult
    func persistRecordingAudio(sources: CaptureSources, meetingID: UUID) async -> SavedRecording {
        guard !sources.isEmpty else { return .none }

        if let sole = sources.soleSource {
            if !sources.needsComposing {
                // The common case: one source, running throughout. Its file is already the timeline.
                return moveIntoPlace(sole.url, meetingID: meetingID, describesTimeline: true)
            }
            // One source that joined late or was muted. Its file holds every sample, just packed
            // together — so the gaps can be spliced in losslessly rather than paying an AAC encode
            // for audio that needs no mixing. Encoding here would block the stop for a minute on a
            // long recording, and hand the transcriber a lossy copy of a file we already have clean.
            if let spliced = await splicePlacements(sole.url, placements: sole.placements, meetingID: meetingID) {
                removeTemporary(sole.url)
                audioRecorder.clearTemporaryFile()
                MeetingStore.shared.setAudioFileURL(spliced, for: meetingID)
                return .onSessionTimeline(spliced)
            }
            logger.warning("Single-source splice failed — falling back to the composition path")
        }

        if let composed = await composeRecording(sources: sources, meetingID: meetingID) {
            MeetingStore.shared.setAudioFileURL(composed, for: meetingID)
            if let system = sources.systemURL, system != composed {
                removeTemporary(system)
            }
            audioRecorder.clearTemporaryFile()
            return .onSessionTimeline(composed)
        }

        // Composition failed. Save a raw file rather than nothing — the audio is all there, and it
        // is better to have it misaligned than not at all. Reported as such so nothing downstream
        // reads timings off it.
        logger.warning("Audio composition failed — saving the raw capture, whose timings may not line up")
        guard let url = sources.systemURL ?? sources.micURL else { return .none }
        return moveIntoPlace(url, meetingID: meetingID, describesTimeline: false)
    }

    private func moveIntoPlace(_ url: URL, meetingID: UUID, describesTimeline: Bool) -> SavedRecording {
        defer { audioRecorder.clearTemporaryFile() }
        do {
            let dest = try moveRecordingFile(from: url, meetingID: meetingID)
            MeetingStore.shared.setAudioFileURL(dest, for: meetingID)
            return describesTimeline ? .onSessionTimeline(dest) : .rawFallback(dest)
        } catch {
            logger.error("Failed to persist recording file: \(error.localizedDescription, privacy: .public)")
            return .none
        }
    }

    private func removeTemporary(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to delete temp audio file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Splicing a single source

    /// Rewrites one source's file with its silent gaps restored, sample for sample.
    ///
    /// A single source records every sample it heard, contiguously — a mute or a late join only
    /// means the file is *shorter* than the meeting, never that audio is missing. So the file can be
    /// copied through with silence inserted at the gaps: no mixing, no encoder, and the result is
    /// still bit-identical PCM. Reserved for the single-source case; two sources genuinely have to be
    /// mixed, which is what `composeRecording` is for.
    private func splicePlacements(
        _ url: URL,
        placements: [CaptureSegmentTimeline.Placement],
        meetingID: UUID
    ) async -> URL? {
        guard !placements.isEmpty else { return nil }
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        guard let outputURL = recordingsFileURL(for: meetingID, extension: ext) else { return nil }
        let capturedLogger = logger

        return await Task.detached {
            do {
                let source = try AVAudioFile(forReading: url)
                let format = source.processingFormat
                let rate = format.sampleRate
                guard rate > 0 else { return nil }
                let destination = try AVAudioFile(forWriting: outputURL, settings: source.fileFormat.settings)

                let blockFrames: AVAudioFrameCount = 1 << 16
                var writtenFrames: AVAudioFramePosition = 0

                for placement in placements.sorted(by: { $0.sessionStart < $1.sessionStart }) {
                    // Silence up to where this activation belongs.
                    let startFrame = AVAudioFramePosition((placement.sessionStart * rate).rounded())
                    if startFrame > writtenFrames {
                        try Self.writeSilence(
                            frames: AVAudioFramePosition(startFrame - writtenFrames),
                            format: format, to: destination, blockFrames: blockFrames
                        )
                        writtenFrames = startFrame
                    }

                    // Then the activation itself, straight through.
                    source.framePosition = AVAudioFramePosition((placement.fileStart * rate).rounded())
                    var remaining = AVAudioFramePosition((placement.duration * rate).rounded())
                    while remaining > 0, source.framePosition < source.length {
                        let count = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames), remaining))
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
                        try source.read(into: buffer, frameCount: count)
                        guard buffer.frameLength > 0 else { break }
                        try destination.write(from: buffer)
                        remaining -= AVAudioFramePosition(buffer.frameLength)
                        writtenFrames += AVAudioFramePosition(buffer.frameLength)
                    }
                }
                return outputURL
            } catch {
                capturedLogger.error("Failed to splice recording: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    nonisolated private static func writeSilence(
        frames: AVAudioFramePosition,
        format: AVAudioFormat,
        to file: AVAudioFile,
        blockFrames: AVAudioFrameCount
    ) throws {
        var remaining = frames
        while remaining > 0 {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames), remaining))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
            buffer.frameLength = count
            // A freshly allocated buffer is already zeroed; set the length and write it.
            try file.write(from: buffer)
            remaining -= AVAudioFramePosition(count)
        }
    }

    // MARK: - Composing

    /// Builds the meeting's audio file, laying every source's activations where they were recorded.
    /// Returns nil if the composition or the export fails.
    func composeRecording(sources: CaptureSources, meetingID: UUID) async -> URL? {
        guard let outputURL = recordingsFileURL(for: meetingID, extension: "m4a") else { return nil }

        let composition = AVMutableComposition()
        do {
            try await addTrack(sources.systemURL, placements: sources.systemPlacements, to: composition)
            try await addTrack(sources.micURL, placements: sources.micPlacements, to: composition)
        } catch {
            logger.error("Failed to build audio composition: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard !composition.tracks.isEmpty else { return nil }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            logger.error("Failed to create AVAssetExportSession for audio mix")
            return nil
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        await exporter.export()

        guard exporter.status == .completed else {
            logger.error("Audio mix export failed: \(exporter.error?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        }
        logger.info("Composed recording → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    /// Adds one source's audio to the composition, each activation at the point it was recorded.
    ///
    /// With no placements — a recording made before they were tracked — the file goes down at the
    /// start, which is where a source that ran throughout belongs. Placements are clamped to the
    /// file's real length so a short-written or truncated file cannot throw.
    private func addTrack(
        _ url: URL?,
        placements: [CaptureSegmentTimeline.Placement],
        to composition: AVMutableComposition
    ) async throws {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else { return }
        guard let track = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        else {
            throw CompositionError.trackCreationFailed
        }

        let duration = try await asset.load(.duration)
        guard placements.isEmpty == false else {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            return
        }

        let fileSeconds = duration.seconds
        for placement in placements {
            let start = max(0, min(placement.fileStart, fileSeconds))
            let length = max(0, min(placement.duration, fileSeconds - start))
            guard length > 0 else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: length, preferredTimescale: 600)
            )
            try track.insertTimeRange(
                range, of: source, at: CMTime(seconds: max(0, placement.sessionStart), preferredTimescale: 600)
            )
        }
    }

    private enum CompositionError: Error {
        case trackCreationFailed
    }

    // MARK: - Locations

    /// Moves a temporary audio file to a stable per-meeting location in Application Support.
    /// Preserves the source file extension (.wav for mic, .caf for system audio).
    private func moveRecordingFile(from tempURL: URL, meetingID: UUID) throws -> URL {
        let ext = tempURL.pathExtension.isEmpty ? "wav" : tempURL.pathExtension
        guard let dest = recordingsFileURL(for: meetingID, extension: ext) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// The per-meeting path in Application Support, with any previous file at it removed.
    private func recordingsFileURL(for meetingID: UUID, extension ext: String) -> URL? {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let recordingsDir = support.appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Recordings directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let dest = recordingsDir.appending(path: "\(meetingID.uuidString).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            do {
                try fm.removeItem(at: dest)
            } catch {
                logger.error("Failed to replace existing recording: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return dest
    }
}
