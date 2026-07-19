import AVFoundation
import Foundation
import os.log

/// Wraps AVAudioPlayer with observable state for SwiftUI playback controls.
/// Supports variable playback rate, scrub-pause, and real-time active-segment tracking.
@Observable
@MainActor
final class AudioPlaybackService: NSObject {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AudioPlayback")

    // MARK: - Published state

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    /// Current playback speed. Applied immediately when playing, or at next play() call.
    var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    /// Transcript segments injected by the view — drives activeSegmentID.
    var segments: [TranscriptSegment] = []
    /// ID of the segment whose time range contains currentTime. Nil when not playing.
    private(set) var activeSegmentID: UUID?

    // MARK: - Internals

    private var player: AVAudioPlayer?
    private let timerLock = OSAllocatedUnfairLock<Timer?>(initialState: nil)
    /// Remembers play state across a scrub so endScrub() can restore it.
    private var wasPlayingBeforeScrub = false

    deinit {
        let timer = timerLock.withLock { stored -> Timer? in let existing = stored; stored = nil; return existing }
        if let timer {
            RunLoop.main.perform { timer.invalidate() }
        }
    }

    // MARK: - Load

    func load(url: URL) {
        stop()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
        } catch {
            logger.error("Failed to load audio file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Transport

    func play() {
        guard let player else { return }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        activeSegmentID = nil
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        activeSegmentID = nil
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration, time))
        currentTime = player.currentTime
        updateActiveSegment(at: currentTime)
    }

    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + seconds)
    }

    // MARK: - Scrub (pause-on-drag)

    /// Call when the scrubber drag begins. Pauses playback and remembers whether to resume.
    func beginScrub() {
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            pause()
        }
    }

    /// Call when the scrubber drag ends. Seeks and resumes if audio was playing before scrub.
    func endScrub(to time: TimeInterval) {
        seek(to: time)
        if wasPlayingBeforeScrub {
            play()
        }
        wasPlayingBeforeScrub = false
    }

    // MARK: - Active Segment

    private func updateActiveSegment(at time: TimeInterval) {
        let active = segments.first { $0.startTime <= time && time < $0.endTime }?.id
        if activeSegmentID != active {
            activeSegmentID = active
        }
    }

    // MARK: - Timer (50ms for smooth scrubber + accurate segment tracking)

    private func startTimer() {
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player else { return }
                currentTime = player.currentTime
                updateActiveSegment(at: player.currentTime)
            }
        }
        timerLock.withLock { $0 = newTimer }
    }

    private func stopTimer() {
        timerLock.withLock { $0?.invalidate(); $0 = nil }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.activeSegmentID = nil
            self.stopTimer()
        }
    }
}
