import Foundation
import os.log

// MARK: - Summary Generation Result

enum SummaryGenerationResult {
    case success(actionItemCount: Int)
    case noActionItems
    case failed(String)
    case skipped
}

// MARK: - AI Title & Summary Generation

extension MeetingStore {
    // MARK: - AI Title Generation (Local LLM)

    func generateAITitle(for meetingID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("generateAITitle: no model loaded")
            return
        }
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else {
            logger.warning("generateAITitle: meeting \(meetingID) not found")
            return
        }

        let transcript = meeting.segments.map(\.text).joined(separator: " ")
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else {
            logger.info("generateAITitle: transcript too short (\(trimmed.count) chars)")
            return
        }

        logger.info("generateAITitle: generating for meeting \(meetingID, privacy: .public) (\(trimmed.count, privacy: .public) chars)")

        let titleSystem = PromptRegistry.Meeting.titleSystem.content

        let prompt = """
        Generate a title for this meeting.

        ---

        <transcript>
        \(String(trimmed.prefix(AppConstants.LLMDefaults.contextWindowSize)))
        </transcript>
        """

        if let cleanTitle = await generateTitle(system: titleSystem, prompt: prompt) {
            if let index = meetings.firstIndex(where: { $0.id == meetingID }),
               isDefaultTitle(meetings[index].title)
            {
                let deduped = uniqueTitle(cleanTitle, among: activeMeetings.map(\.title))
                logger.info("generateAITitle: title set for meeting \(meetingID, privacy: .public)")
                meetings[index].title = deduped
                meetings[index].modifiedAt = Date()
                saveMeeting(id: meetingID)
            } else {
                logger.info("generateAITitle: skipped — title already customized")
            }
        }
    }

    /// Re-generate a title, considering the current title and content changes.
    func regenerateAITitle(for meetingID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("regenerateAITitle: no model loaded")
            return
        }
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else {
            logger.warning("regenerateAITitle: meeting \(meetingID) not found")
            return
        }

        let transcript = meeting.segments.map(\.text).joined(separator: " ")
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else {
            logger.info("regenerateAITitle: transcript too short (\(trimmed.count) chars)")
            return
        }

        let currentTitle = meeting.title
        logger.info("regenerateAITitle: starting for meeting \(meetingID, privacy: .public) (\(trimmed.count, privacy: .public) chars)")

        let titleSystem = if isDefaultTitle(currentTitle) {
            PromptRegistry.Meeting.titleSystem.content
        } else {
            PromptRegistry.Meeting.titleRegenerateSystem(currentTitle: currentTitle).content
        }

        let prompt = """
        Generate a title for this meeting.

        ---

        <transcript>
        \(String(trimmed.prefix(AppConstants.LLMDefaults.contextWindowSize)))
        </transcript>
        """

        if let cleanTitle = await generateTitle(system: titleSystem, prompt: prompt) {
            if let index = meetings.firstIndex(where: { $0.id == meetingID }) {
                logger.info("regenerateAITitle: title updated for meeting \(meetingID, privacy: .public)")
                meetings[index].title = cleanTitle
                meetings[index].modifiedAt = Date()
                saveMeeting(id: meetingID)
            }
        }
    }

    // MARK: - AI Summary Generation (Local LLM)

    @discardableResult
    // swiftlint:disable:next function_body_length
    func generateAISummary(for meetingID: UUID) async -> SummaryGenerationResult {
        guard !generatingMeetingIDs.contains(meetingID) else {
            logger.info("generateAISummary: already in progress for \(meetingID)")
            return .skipped
        }
        generatingMeetingIDs.insert(meetingID)
        defer { generatingMeetingIDs.remove(meetingID) }

        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("generateAISummary: no model loaded")
            return .skipped
        }
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return .skipped }
        guard !meeting.segments.isEmpty else { return .skipped }

        let fullTranscript = meeting.fullTranscript
        guard fullTranscript.count > 20 else { return .skipped }

        // Truncate transcript to fit within model context window (~4 chars/token heuristic).
        // Reserve tokens for output + system prompt/speaker context.
        let maxInputChars = LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.summaryReservedTokens)
        let transcript: String
        if fullTranscript.count > maxInputChars {
            transcript = String(fullTranscript.prefix(maxInputChars))
            logger.warning("Transcript truncated from \(fullTranscript.count) to \(maxInputChars) chars to fit context window")
        } else {
            transcript = fullTranscript
        }

        let speakerContext = buildSpeakerContext(for: meeting)
        let template = meeting.template

        do {
            let result = try await withRetry {
                try await LLMEngine.shared.complete(
                    system: PromptRegistry.withBase(MeetingPromptBuilder.summarySystemInstructions(template: template)),
                    prompt: MeetingPromptBuilder.summaryPrompt(transcript: transcript) + speakerContext,
                    maxTokens: 2048
                )
            }

            var smartMinutes = MeetingPromptBuilder.parseSmartMinutes(from: result)
            var parsedSummary = MeetingPromptBuilder.parseSummaryText(from: result)

            // If JSON parse failed, retry once with stricter format instructions
            if smartMinutes == nil, parsedSummary == nil {
                logger.warning("Smart Minutes JSON parse failed — retrying with stricter format prompt")
                let retryResult = try await LLMEngine.shared.complete(
                    system: PromptRegistry.Meeting.summaryStrictSystem(template: template),
                    prompt: MeetingPromptBuilder.summaryPrompt(transcript: String(transcript.prefix(2000))) + speakerContext,
                    maxTokens: 2048
                )
                smartMinutes = MeetingPromptBuilder.parseSmartMinutes(from: retryResult)
                parsedSummary = MeetingPromptBuilder.parseSummaryText(from: retryResult)
            }

            if let smartMinutes {
                setSmartMinutes(smartMinutes, for: meetingID)
            }

            if let parsedSummary {
                setSummary(parsedSummary, for: meetingID)
            } else {
                // Final fallback: plain-text summary
                logger.warning("Structured JSON failed after retry — using plain-text fallback")
                let fallback = try await LLMEngine.shared.complete(
                    system: PromptRegistry.Meeting.summaryFallbackSystem.content,
                    prompt: "<transcript>\n\(String(transcript.prefix(2000)))\n</transcript>"
                )
                if !fallback.isEmpty {
                    setSummary(fallback, for: meetingID)
                }
            }

            let storedActionItemCount = storeActionItems(from: result, smartMinutes: smartMinutes, meetingID: meetingID)

            let keywords = MeetingPromptBuilder.parseTopicKeywords(from: result)
            if !keywords.isEmpty {
                setTopicKeywords(keywords, for: meetingID)
            }

            logger.info("AI summary generated for meeting \(meetingID, privacy: .public)")

            return storedActionItemCount > 0 ? .success(actionItemCount: storedActionItemCount) : .noActionItems
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Smart Highlights

    /// Extracts 5-10 navigable highlights from the transcript via LLM and persists them
    /// as AI-sourced Bookmarks on the meeting. Existing AI bookmarks are replaced; manual
    /// bookmarks are preserved. No-op if the meeting is too short or the model is missing.
    func generateAIHighlights(for meetingID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("generateAIHighlights: no model loaded")
            return
        }
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        guard !meeting.segments.isEmpty else { return }

        // Skip very short recordings — highlights don't add value over the summary.
        let minDurationForHighlights: TimeInterval = 60 // 1 minute
        guard meeting.duration >= minDurationForHighlights else {
            logger.info("generateAIHighlights: meeting too short (\(meeting.duration)s)")
            return
        }

        let maxInputChars = LLMEngine.maxInputChars(reservedTokens: 1024)
        let prompt = MeetingPromptBuilder.highlightsPrompt(
            segments: meeting.segments,
            maxChars: maxInputChars
        )

        do {
            let raw = try await withRetry {
                try await LLMEngine.shared.complete(
                    system: PromptRegistry.Meeting.highlightsSystem.content,
                    prompt: prompt,
                    maxTokens: 1024
                )
            }

            let highlights = MeetingPromptBuilder.parseHighlights(
                from: raw,
                meetingDuration: meeting.duration
            )

            guard !highlights.isEmpty else {
                logger.warning("generateAIHighlights: no highlights parsed from LLM response")
                return
            }

            await replaceAIBookmarks(with: highlights, for: meetingID)
            logger.info("generateAIHighlights: added \(highlights.count) highlights to meeting \(meetingID, privacy: .public)")
        } catch {
            logger.error("generateAIHighlights: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replaces all `.ai`-sourced bookmarks on a meeting with the provided set, preserving manual bookmarks.
    /// Sorts the combined list by timestamp so the panel renders in chronological order.
    private func replaceAIBookmarks(with aiBookmarks: [Bookmark], for meetingID: UUID) async {
        guard let index = meetingIndex(for: meetingID) else { return }
        let manual = meetings[index].bookmarks.filter { $0.source == .manual }
        let combined = (manual + aiBookmarks).sorted { $0.timestamp < $1.timestamp }
        meetings[index].bookmarks = combined
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    // MARK: - Helpers

    /// Parse and store action items from LLM result, returns count stored.
    private func storeActionItems(from result: String, smartMinutes: SmartMinutes?, meetingID: UUID) -> Int {
        let actionItems = MeetingPromptBuilder.parseActionItems(from: result)
        if !actionItems.isEmpty {
            setActionItems(actionItems, for: meetingID)
            return actionItems.count
        } else if let smartMinutes, !smartMinutes.actionItems.isEmpty {
            let fallbackItems = smartMinutes.actionItems.map { ActionItem(title: $0) }
            setActionItems(fallbackItems, for: meetingID)
            logger.info("Used SmartMinutes fallback for \(fallbackItems.count) action items")
            return fallbackItems.count
        }
        return 0
    }

    /// A1/A6: Generates a title using the local LLM via LLMEngine with centralized retry.
    func generateTitle(system: String? = nil, prompt: String) async -> String? {
        await AITitleGenerator.generate(system: system, prompt: prompt)
    }

    /// Returns true if the title was auto-generated (not user-customized).
    /// Bug-1 fix: Voice Note uses Date.formatted(.abbreviated) which produces locale-dependent output,
    /// so we use hasPrefix instead of a strict date regex.
    func isDefaultTitle(_ title: String) -> Bool {
        title == "Untitled Meeting"
            || title.range(of: #"^Meeting \d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            || title.hasPrefix("Voice Note ")
    }

    // MARK: - AI Space Suggestion

    /// Suggests which existing Space a meeting should be filed in, based on its transcript and topic keywords.
    /// Returns the suggested space ID, or `nil` if no good match is found.
    func suggestSpace(for meetingID: UUID) async -> UUID? {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("suggestSpace: no model loaded")
            return nil
        }
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return nil }

        let spaces = SpaceStore.shared.spaces
        guard !spaces.isEmpty else { return nil }

        // Build context about the meeting
        let transcript = String(meeting.fullTranscript.prefix(600))
        let title = meeting.title
        let keywords = meeting.topicKeywords
        let spaceDescriptions = buildSpaceDescriptions(for: spaces)

        let sanitizedTitle = String(title.prefix(200))
        let sanitizedKeywords = keywords.map { String($0.prefix(50)) }.joined(separator: ", ")

        let prompt = """
        Which Space does this meeting belong in? Respond with ONLY the Space ID (8-character prefix) or "NONE".

        ---

        MEETING:
        Title: \(sanitizedTitle)
        Keywords: \(sanitizedKeywords)
        <transcript>
        \(transcript)
        </transcript>

        AVAILABLE SPACES:
        \(spaceDescriptions.joined(separator: "\n"))
        """

        guard let result = await withRetryOptional(operation: {
            try await LLMEngine.shared.complete(
                system: PromptRegistry.Meeting.spaceSuggestSystem.content,
                prompt: prompt,
                maxTokens: 32
            )
        })
        else { return nil }

        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "none" || cleaned.isEmpty {
            return nil
        }

        // Match the 8-char prefix back to a space
        let matched = spaces.first { space in
            let prefix = String(space.id.uuidString.prefix(8)).lowercased()
            return cleaned.contains(prefix)
        }

        if let matched {
            logger.info("suggestSpace: suggested space \(matched.id, privacy: .public) for meeting \(meetingID, privacy: .public)")
        }
        return matched?.id
    }

    // MARK: - Helpers

    private func buildSpaceDescriptions(for spaces: [Space]) -> [String] {
        // Limit to 10 spaces to prevent prompt overflow with many workspaces
        spaces.prefix(10).map { space in
            let docs = DocumentStore.shared.documents(inSpace: space.id)
            let spaceMeetings = meetings(inSpace: space.id)
            // Sanitize user-controlled content: truncate and strip control characters
            let sanitize: (String) -> String = { String($0.prefix(100)).filter { !$0.isNewline && $0.asciiValue != 0 } }
            let contentTitles = (docs.map(\.title) + spaceMeetings.map(\.title)).prefix(5).map(sanitize)
            let keywordList = Array(Set(spaceMeetings.flatMap(\.topicKeywords))).prefix(5).map(sanitize)
            var desc = "- \(sanitize(space.name)) (ID: \(space.id.uuidString.prefix(8)))"
            if !contentTitles.isEmpty {
                desc += " [contains: \(contentTitles.joined(separator: ", "))]"
            }
            if !keywordList.isEmpty {
                desc += " [topics: \(keywordList.joined(separator: ", "))]"
            }
            return desc
        }
    }

    private func buildSpeakerContext(for meeting: MeetingNote) -> String {
        guard meeting.hasSpeakerData, !meeting.speakers.isEmpty else { return "" }
        let totalDuration = meeting.duration
        var speakerDetails: [String] = []
        for speaker in meeting.speakers {
            let speakerTime = meeting.speakerSegments
                .filter { $0.speakerId == speaker.id }
                .reduce(0.0) { $0 + $1.duration }
            let percent = totalDuration > 0 ? (speakerTime / totalDuration) * 100 : 0
            speakerDetails.append("\(speaker.name): \(Int(percent.rounded()))% speaking time")
        }
        return """
        \nSPEAKERS IDENTIFIED (with measured speaking time):
        \(speakerDetails.joined(separator: "\n"))
        IMPORTANT: Include ALL speakers in the attendeeSummary. Use the speaking time percentages above.\n
        """
    }
}
