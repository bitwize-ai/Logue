import AVFoundation
import Foundation
import os.log

/// Text-to-speech service for reading meeting summaries aloud.
/// Uses AVSpeechSynthesizer with on-device voices. Tracks current section
/// so the UI can highlight what's being read.
@Observable
@MainActor
final class SummaryNarrationService: NSObject {
    static let shared = SummaryNarrationService()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SummaryNarration")

    // MARK: - State

    enum PlaybackState {
        case idle
        case playing
        case paused
    }

    private(set) var playbackState: PlaybackState = .idle
    /// Index of the section currently being spoken (for UI highlighting).
    private(set) var currentSectionIndex: Int = 0
    /// Total number of sections queued for narration.
    private(set) var totalSections: Int = 0
    /// The meeting ID currently being narrated.
    private(set) var activeMeetingID: UUID?

    // MARK: - Internals

    private let synthesizer = AVSpeechSynthesizer()
    private var sections: [NarrationSection] = []
    private var currentUtteranceIndex: Int = 0

    private struct NarrationSection {
        let label: String
        let text: String
        let sectionIndex: Int
    }

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Start narrating a meeting's summary from the beginning.
    func play(meeting: MeetingNote) {
        stop()

        sections = buildSections(from: meeting)
        guard !sections.isEmpty else {
            logger.info("Nothing to narrate for meeting: \(meeting.title, privacy: .private)")
            return
        }

        activeMeetingID = meeting.id
        totalSections = sectionCount(from: meeting)
        currentUtteranceIndex = 0
        currentSectionIndex = sections.first?.sectionIndex ?? 0
        playbackState = .playing

        speakNext()
    }

    /// Toggle between play and pause.
    func togglePlayPause() {
        switch playbackState {
        case .playing:
            pause()
        case .paused:
            resume()
        case .idle:
            break
        }
    }

    /// Pause narration.
    func pause() {
        guard playbackState == .playing else { return }
        synthesizer.pauseSpeaking(at: .word)
        playbackState = .paused
    }

    /// Resume narration from where it was paused.
    func resume() {
        guard playbackState == .paused else { return }
        synthesizer.continueSpeaking()
        playbackState = .playing
    }

    /// Stop narration entirely.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        playbackState = .idle
        currentSectionIndex = 0
        currentUtteranceIndex = 0
        totalSections = 0
        sections = []
        activeMeetingID = nil
    }

    /// Skip to the next section.
    func skipForward() {
        guard playbackState != .idle else { return }

        // Find the next section boundary
        let currentSection = sections[safe: currentUtteranceIndex]?.sectionIndex ?? 0
        if let nextIdx = sections.dropFirst(currentUtteranceIndex).firstIndex(where: { $0.sectionIndex > currentSection }) {
            synthesizer.stopSpeaking(at: .immediate)
            currentUtteranceIndex = nextIdx
            currentSectionIndex = sections[nextIdx].sectionIndex
            playbackState = .playing
            speakNext()
        } else {
            stop()
        }
    }

    /// Skip to the previous section.
    func skipBackward() {
        guard playbackState != .idle else { return }

        let currentSection = sections[safe: currentUtteranceIndex]?.sectionIndex ?? 0
        let targetSection = max(0, currentSection - 1)
        if let prevIdx = sections.firstIndex(where: { $0.sectionIndex == targetSection }) {
            synthesizer.stopSpeaking(at: .immediate)
            currentUtteranceIndex = prevIdx
            currentSectionIndex = targetSection
            playbackState = .playing
            speakNext()
        }
    }

    // MARK: - Speech

    private func speakNext() {
        guard currentUtteranceIndex < sections.count else {
            stop()
            return
        }

        let section = sections[currentUtteranceIndex]
        currentSectionIndex = section.sectionIndex

        let utterance = AVSpeechUtterance(string: section.text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = section.label.isEmpty ? 0.1 : 0.3

        // Prefer a high-quality voice
        if let voice = preferredVoice() {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return voices.first
    }

    // MARK: - Section Building

    private func buildSections(from meeting: MeetingNote) -> [NarrationSection] {
        var result: [NarrationSection] = []
        var sectionIdx = 0

        // Overview summary
        if let summary = meeting.summary, !summary.isEmpty {
            result.append(NarrationSection(label: "Summary", text: summary, sectionIndex: sectionIdx))
            sectionIdx += 1
        }

        guard let minutes = meeting.smartMinutes else { return result }

        // Key Decisions
        if !minutes.keyDecisions.isEmpty {
            result.append(NarrationSection(label: "Key Decisions", text: "Key Decisions.", sectionIndex: sectionIdx))
            for decision in minutes.keyDecisions {
                result.append(NarrationSection(label: "", text: decision, sectionIndex: sectionIdx))
            }
            sectionIdx += 1
        }

        // Discussion Points
        if !minutes.discussionPoints.isEmpty {
            result.append(NarrationSection(label: "Discussion Points", text: "Discussion Points.", sectionIndex: sectionIdx))
            for point in minutes.discussionPoints {
                result.append(NarrationSection(label: "", text: point, sectionIndex: sectionIdx))
            }
            sectionIdx += 1
        }

        // Action Items
        if !minutes.actionItems.isEmpty {
            result.append(NarrationSection(label: "Action Items", text: "Action Items.", sectionIndex: sectionIdx))
            for (i, item) in minutes.actionItems.enumerated() {
                result.append(NarrationSection(label: "", text: "\(i + 1). \(item)", sectionIndex: sectionIdx))
            }
            sectionIdx += 1
        }

        // Follow-ups
        if !minutes.followUps.isEmpty {
            result.append(NarrationSection(label: "Follow-ups", text: "Follow-ups.", sectionIndex: sectionIdx))
            for followUp in minutes.followUps {
                result.append(NarrationSection(label: "", text: followUp, sectionIndex: sectionIdx))
            }
            sectionIdx += 1
        }

        // Attendees
        if !minutes.attendeeSummary.isEmpty {
            result.append(NarrationSection(label: "Attendees", text: "Attendee Summary.", sectionIndex: sectionIdx))
            for attendee in minutes.attendeeSummary {
                let points = attendee.keyPoints.joined(separator: ". ")
                let text = "\(attendee.name). \(points)"
                result.append(NarrationSection(label: "", text: text, sectionIndex: sectionIdx))
            }
        }

        return result
    }

    private func sectionCount(from meeting: MeetingNote) -> Int {
        var count = 0
        if meeting.summary != nil {
            count += 1
        }
        guard let minutes = meeting.smartMinutes else { return max(count, 1) }
        if !minutes.keyDecisions.isEmpty {
            count += 1
        }
        if !minutes.discussionPoints.isEmpty {
            count += 1
        }
        if !minutes.actionItems.isEmpty {
            count += 1
        }
        if !minutes.followUps.isEmpty {
            count += 1
        }
        if !minutes.attendeeSummary.isEmpty {
            count += 1
        }
        return max(count, 1)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SummaryNarrationService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentUtteranceIndex += 1
            if self.currentUtteranceIndex < self.sections.count {
                self.speakNext()
            } else {
                self.stop()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancellation is handled by stop()/skipForward()/skipBackward()
    }
}

// MARK: - Collection Safety

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
