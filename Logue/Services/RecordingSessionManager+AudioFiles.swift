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
    }

    // MARK: - Persisting

    /// Saves the session's audio for playback on the meeting's own timeline.
    ///
    /// A single source that ran once from the start of the meeting is moved into place untouched —
    /// the common case, and the only one where the raw file already is the timeline. Everything else
    /// is composed, including a single source, because a mute or a late join means it is not.
    func persistRecordingAudio(sources: CaptureSources, meetingID: UUID) async {
        let system = sources.systemURL
        let mic = sources.micURL

        // Untouched only when there is one source and its file already lines up with the meeting.
        let singleSource: (url: URL, placements: [CaptureSegmentTimeline.Placement])? =
            switch (system, mic) {
            case let (url?, nil): (url, sources.systemPlacements)
            case let (nil, url?): (url, sources.micPlacements)
            default: nil
            }
        if let singleSource, CaptureSegmentTimeline.fileMatchesSessionTimeline(singleSource.placements) {
            moveIntoPlace(singleSource.url, meetingID: meetingID)
            return
        }

        if let composed = await composeRecording(sources: sources, meetingID: meetingID) {
            MeetingStore.shared.setAudioFileURL(composed, for: meetingID)
            if let system, system != composed {
                removeTemporary(system)
            }
            audioRecorder.clearTemporaryFile()
            return
        }

        // Composition failed. Save a raw file rather than nothing — its timing may be off where a
        // source was muted, but the audio itself is all there.
        logger.warning("Audio composition failed — saving the raw capture instead")
        if let url = system ?? mic {
            moveIntoPlace(url, meetingID: meetingID)
        }
    }

    private func moveIntoPlace(_ url: URL, meetingID: UUID) {
        do {
            let dest = try moveRecordingFile(from: url, meetingID: meetingID)
            MeetingStore.shared.setAudioFileURL(dest, for: meetingID)
        } catch {
            logger.error("Failed to persist recording file: \(error.localizedDescription, privacy: .public)")
        }
        audioRecorder.clearTemporaryFile()
    }

    private func removeTemporary(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to delete temp audio file: \(error.localizedDescription, privacy: .public)")
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
    /// Internal rather than private: the core file calls it when a recording stops.
    func moveRecordingFile(from tempURL: URL, meetingID: UUID) throws -> URL {
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
