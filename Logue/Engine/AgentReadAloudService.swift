import AVFoundation
import Foundation
import os.log

/// Reads agent assistant messages aloud via `AVSpeechSynthesizer`.
/// Mirrors `SummaryNarrationService`'s architecture but simplified to one
/// utterance per call — agent responses are typically short and don't need
/// section navigation.
///
/// Strips Markdown noise (headings, code fences, link syntax, list bullets)
/// before speaking so the user doesn't hear "asterisk asterisk hello asterisk
/// asterisk" for `**hello**`.
@Observable
@MainActor
final class AgentReadAloudService: NSObject {
    static let shared = AgentReadAloudService()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AgentReadAloud")
    private let synthesizer = AVSpeechSynthesizer()

    /// The content currently being spoken (or nil when idle). Used by the
    /// Speak button to flip between "Speak" and "Stop" without any extra state.
    private(set) var activeContent: String?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// True if `content` is what's currently playing. The Speak button uses
    /// this to determine its icon.
    func isSpeaking(content: String) -> Bool {
        activeContent == content && synthesizer.isSpeaking
    }

    /// Speak `content` aloud. If anything is already playing, it's interrupted.
    func speak(_ content: String) {
        let cleaned = Self.cleanMarkdown(content)
        guard !cleaned.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeContent = content
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        if let voice = preferredVoice() {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// Cancel anything currently playing.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeContent = nil
    }

    // MARK: - Voice

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return voices.first
    }

    // MARK: - Markdown stripping

    /// Removes Markdown noise so the synthesizer reads natural prose. Targets
    /// the common forms agent output produces — headings, fences, link syntax,
    /// bullets, emphasis. Not exhaustive; just enough to avoid character-by-character
    /// pronunciation of formatting.
    private static func cleanMarkdown(_ text: String) -> String {
        // Skip the regex chain entirely on empty input — it would produce
        // empty anyway, and `speak()` already short-circuits on empty.
        guard !text.isEmpty else { return "" }
        var cleaned = text

        // Strip fenced code blocks entirely — reading code aloud is noise.
        cleaned = cleaned.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: " (code block) ",
            options: .regularExpression
        )
        // Inline code → just speak the contents.
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        // Image syntax ![alt](url) → read alt only.
        cleaned = cleaned.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        // Link syntax [text](url) → read text only.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        // Heading markers at line start (`# `, `## `, etc.).
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )
        // Bullet list markers (`- `, `* `, `+ `, `1. `).
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)^\\s*[-*+]\\s+",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)^\\s*\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )
        // Emphasis: **bold**, *italic*, ~~strike~~.
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "~~", with: "")
        cleaned = cleaned.replacingOccurrences(
            of: "(?<!\\w)\\*(?!\\s)([^*]+?)\\*(?!\\w)",
            with: "$1",
            options: .regularExpression
        )
        // Block quotes.
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)^>\\s+",
            with: "",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AgentReadAloudService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeContent = nil
        }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeContent = nil
        }
    }
}
