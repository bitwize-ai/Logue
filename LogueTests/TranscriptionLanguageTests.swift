import Foundation
@testable import Logue
import Testing

@Suite("TranscriptionLanguage")
struct TranscriptionLanguageTests {
    @Test("German maps to de-DE")
    func germanLocale() {
        #expect(TranscriptionLanguage.german.locale?.language.languageCode?.identifier == "de")
    }

    @Test("Auto has no canonical locale of its own")
    func autoHasNoCanonicalLocale() {
        #expect(TranscriptionLanguage.auto.locale == nil)
    }

    @Test("Auto follows the first preferred language we support")
    func autoFollowsPreferredLanguage() {
        let locale = TranscriptionLanguage.auto.resolvedSpeechLocale(
            preferredLanguages: ["de-DE", "en-US"],
            fallback: Locale(identifier: "en-US")
        )
        #expect(locale.language.languageCode?.identifier == "de")
    }

    @Test("Auto skips preferred languages that have no Speech mapping")
    func autoSkipsUnsupportedPreferredLanguages() {
        let locale = TranscriptionLanguage.auto.resolvedSpeechLocale(
            preferredLanguages: ["sv-SE", "de-AT"],
            fallback: Locale(identifier: "en-US")
        )
        #expect(locale.language.languageCode?.identifier == "de")
    }

    @Test("Auto uses the fallback when nothing in the preferred list is supported")
    func autoUsesFallback() {
        let fallback = Locale(identifier: "fr-FR")
        let locale = TranscriptionLanguage.auto.resolvedSpeechLocale(
            preferredLanguages: ["sv-SE", "fi-FI"],
            fallback: fallback
        )
        #expect(locale.language.languageCode?.identifier == "fr")
    }

    @Test("An explicit language ignores the Mac preferred-language list")
    func explicitGermanIgnoresPreferred() {
        let locale = TranscriptionLanguage.german.resolvedSpeechLocale(
            preferredLanguages: ["en-US"],
            fallback: Locale(identifier: "en-US")
        )
        #expect(locale.language.languageCode?.identifier == "de")
    }

    @Test("A meeting with no stored language uses the Settings default")
    func nilStoredUsesDefault() throws {
        let suiteName = "TranscriptionLanguageTests.nilStored"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        suite.set("de", forKey: AppConstants.UserDefaultsKeys.defaultTranscriptionLanguage)
        #expect(TranscriptionLanguage.resolved(fromStored: nil, defaults: suite) == .german)
    }

    @Test("A meeting's stored language wins over the Settings default")
    func storedMeetingLanguageWins() throws {
        let suiteName = "TranscriptionLanguageTests.storedWins"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        suite.set("en", forKey: AppConstants.UserDefaultsKeys.defaultTranscriptionLanguage)
        #expect(TranscriptionLanguage.resolved(fromStored: "de", defaults: suite) == .german)
    }

    @Test("A missing Settings key is Auto")
    func missingDefaultsIsAuto() throws {
        let suiteName = "TranscriptionLanguageTests.missing"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        #expect(TranscriptionLanguage.storedDefault(from: suite) == .auto)
    }

    @Test("matchingLocale falls back from a regional variant to the same language")
    func matchingLocaleLanguageCode() {
        let supported = [Locale(identifier: "de-DE"), Locale(identifier: "en-US")]
        let match = TranscriptionLanguage.matchingLocale(for: Locale(identifier: "de-AT"), in: supported)
        #expect(match?.language.languageCode?.identifier == "de")
    }

    @Test("Auto preferred language de uses canonical de-DE, not a bare de tag")
    func autoBareLanguageCodeUsesCanonicalLocale() {
        let locale = TranscriptionLanguage.auto.resolvedSpeechLocale(
            preferredLanguages: ["de"],
            fallback: Locale(identifier: "en-US")
        )
        #expect(locale.identifier == "de-DE" || locale.identifier == "de_DE")
    }

    @Test("speechLocaleCandidates prefer Apple's equivalent then other German locales")
    func speechLocaleCandidatesOrder() {
        let requested = Locale(identifier: "de-DE")
        let equivalent = Locale(identifier: "de-DE")
        let supported = [
            Locale(identifier: "de-AT"),
            Locale(identifier: "de-DE"),
            Locale(identifier: "en-US"),
        ]
        let candidates = TranscriptionLanguage.speechLocaleCandidates(
            requested: requested,
            equivalent: equivalent,
            supported: supported
        )
        #expect(candidates.first?.language.languageCode?.identifier == "de")
        #expect(candidates.contains { $0.identifier == "de-AT" || $0.identifier == "de_AT" })
        #expect(!candidates.contains { $0.language.languageCode?.identifier == "en" })
    }

    @Test("Apple Not Installing errors are treated as a missing SpeechTranscriber asset")
    func speechAssetUnavailableDetection() {
        #expect(
            TranscriptionLanguage.isSpeechAssetUnavailable(
                "transcription.de asset unavailable after attempted download, final state: Not Installing"
            )
        )
        #expect(!TranscriptionLanguage.isSpeechAssetUnavailable("No compatible audio format found."))
    }

    @Test("workingLocale keeps the request when Speech has not enumerated locales yet")
    func workingLocaleEmptySupported() {
        let requested = Locale(identifier: "de-DE")
        let result = TranscriptionLanguage.workingLocale(
            requested: requested,
            supported: [],
            fallbacks: [Locale(identifier: "en-US")],
            allowLanguageFallback: true
        )
        #expect(result?.language.languageCode?.identifier == "de")
    }

    @Test("workingLocale does not silently switch a chosen language to English")
    func workingLocaleNoEnglishFallbackWhenChosen() {
        let result = TranscriptionLanguage.workingLocale(
            requested: Locale(identifier: "de-DE"),
            supported: [Locale(identifier: "en-US"), Locale(identifier: "fr-FR")],
            fallbacks: [Locale(identifier: "en-US")],
            allowLanguageFallback: false
        )
        #expect(result == nil)
    }

    @Test("workingLocale may fall back to English only for Auto")
    func workingLocaleEnglishFallbackForAuto() {
        let result = TranscriptionLanguage.workingLocale(
            requested: Locale(identifier: "sv-SE"),
            supported: [Locale(identifier: "en-US"), Locale(identifier: "fr-FR")],
            fallbacks: [Locale(identifier: "en-US")],
            allowLanguageFallback: true
        )
        #expect(result?.language.languageCode?.identifier == "en")
    }

    @Test("MeetingNote round-trips transcriptionLanguage")
    func meetingNoteRoundTrip() throws {
        let meeting = MeetingNote(title: "Standup", transcriptionLanguage: "de")
        let data = try JSONEncoder().encode(meeting)
        let decoded = try JSONDecoder().decode(MeetingNote.self, from: data)
        #expect(decoded.transcriptionLanguage == "de")
    }

    @Test("German Smart Minutes prompts ask for German prose")
    func germanSummaryInstruction() {
        let instruction = TranscriptionLanguage.german.outputLanguageInstruction
        #expect(instruction.contains("German"))
        #expect(instruction.contains("Do not translate into English"))
        let prompt = MeetingPromptBuilder.summarySystemInstructions(template: .general, language: .german)
        #expect(prompt.contains(instruction))
    }

    @Test("Auto Smart Minutes follow the transcript language")
    func autoSummaryInstructionFollowsTranscript() {
        let instruction = TranscriptionLanguage.auto.outputLanguageInstruction
        #expect(instruction.contains("same language as the transcript"))
    }

    @Test("German notes documents use German section headings")
    func germanMarkdownHeadings() {
        var meeting = MeetingNote(title: "Standup", transcriptionLanguage: "de")
        meeting.summary = "Kurzer Überblick."
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: ["Wir nehmen Option A."],
            discussionPoints: [],
            actionItems: [],
            followUps: [],
            attendeeSummary: []
        )
        let markdown = meeting.smartMinutesMarkdown()
        #expect(markdown.contains("**Datum:**"))
        #expect(markdown.contains("## Wichtige Entscheidungen"))
        #expect(!markdown.contains("**Date:**"))
        #expect(!markdown.contains("## Key Decisions"))
    }
}
