import AVFoundation
import Foundation

/// Where a finished recording's audio ends up on disk. Extracted from the recording state machine:
/// these are pure file operations with no bearing on the recording lifecycle, and the state machine
/// is long enough without them.
extension RecordingSessionManager {
    /// Mixes system audio and mic audio into a single M4A file saved to the Recordings directory.
    /// The longer track defines the total duration.
    ///
    /// `micPlacements` says where each stretch of the mic file belongs on the meeting's timeline.
    /// The mic writes one file across every mute and unmute with the muted stretches absent from it,
    /// so laying the file down as a single run plays everything after the first mute early, by more
    /// and more with each toggle. Each activation is inserted at the point it was actually recorded.
    ///
    /// Returns nil if mixing fails; caller should fall back to system-audio-only.
    /// Internal rather than private: the core file calls it when a recording stops.
    func mixAudioFiles(
        systemURL: URL,
        micURL: URL,
        micPlacements: [MicSegmentTimeline.Placement],
        meetingID: UUID
    ) async -> URL? {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let recordingsDir = support.appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        try? fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let outputURL = recordingsDir.appending(path: "\(meetingID.uuidString).m4a")
        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(at: outputURL)
        }

        let systemAsset = AVURLAsset(url: systemURL)
        let micAsset = AVURLAsset(url: micURL)
        let composition = AVMutableComposition()

        guard let sysTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
            let micTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            logger.error("Failed to create composition tracks for audio mix")
            return nil
        }

        do {
            let sysSrcTracks = try await systemAsset.loadTracks(withMediaType: .audio)
            let micSrcTracks = try await micAsset.loadTracks(withMediaType: .audio)

            if let src = sysSrcTracks.first {
                let dur = try await systemAsset.load(.duration)
                try sysTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
            }
            if let src = micSrcTracks.first {
                let micDuration = try await micAsset.load(.duration)
                try insertMic(src, duration: micDuration, placements: micPlacements, into: micTrack)
            }
        } catch {
            logger.error("Failed to build audio composition: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        )
        else {
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

        logger.info("Mixed system + mic audio → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    /// Lays each mic activation into the composition at the point on the meeting it was recorded.
    ///
    /// With no placements — a recording that predates them, or one where the mic never stopped — the
    /// whole file goes down at the start, which is where it belongs in both cases. Placements are
    /// clamped to the file's real length so a truncated or short-written file cannot throw.
    private func insertMic(
        _ source: AVAssetTrack,
        duration: CMTime,
        placements: [MicSegmentTimeline.Placement],
        into track: AVMutableCompositionTrack
    ) throws {
        guard !placements.isEmpty else {
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
            let at = CMTime(seconds: max(0, placement.sessionStart), preferredTimescale: 600)
            try track.insertTimeRange(range, of: source, at: at)
        }
    }

    /// Moves a temporary audio file to a stable per-meeting location in Application Support.
    /// Preserves the source file extension (.wav for mic, .caf for system audio).
    /// Internal rather than private: the core file calls it when a recording stops.
    func moveRecordingFile(from tempURL: URL, meetingID: UUID) throws -> URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let recordingsDir = support.appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let ext = tempURL.pathExtension.isEmpty ? "wav" : tempURL.pathExtension
        let dest = recordingsDir.appending(path: "\(meetingID.uuidString).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// Saves the session's audio for playback, choosing by which sources actually recorded:
    /// both (online meeting with the mic on) are mixed into one file, otherwise the single
    /// source is moved into place as it is.
    func persistRecordingAudio(
        systemTempURL: URL?,
        micPlacements: [MicSegmentTimeline.Placement],
        meetingID: UUID
    ) async {
        do {
            if let sysURL = systemTempURL, let micURL = audioRecorder.tempFileURL {
                if let mixedURL = await mixAudioFiles(
                    systemURL: sysURL,
                    micURL: micURL,
                    micPlacements: micPlacements,
                    meetingID: meetingID
                ) {
                    MeetingStore.shared.setAudioFileURL(mixedURL, for: meetingID)
                    try? FileManager.default.removeItem(at: sysURL)
                } else {
                    // Mix failed — fall back to system audio only
                    let url = try moveRecordingFile(from: sysURL, meetingID: meetingID)
                    MeetingStore.shared.setAudioFileURL(url, for: meetingID)
                }
            } else if let sysURL = systemTempURL {
                let url = try moveRecordingFile(from: sysURL, meetingID: meetingID)
                MeetingStore.shared.setAudioFileURL(url, for: meetingID)
            } else if let micURL = audioRecorder.tempFileURL {
                let url = try moveRecordingFile(from: micURL, meetingID: meetingID)
                MeetingStore.shared.setAudioFileURL(url, for: meetingID)
            }
        } catch {
            logger.error("Failed to persist recording file: \(error.localizedDescription, privacy: .public)")
        }
        audioRecorder.clearTemporaryFile()
    }
}
