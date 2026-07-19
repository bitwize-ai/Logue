import SwiftUI

/// Collapsible daily digest card shown above the meeting grid when today has summarized meetings.
struct DailyDigestCard: View {
    @Environment(MeetingStore.self) private var store

    @State private var isGenerating = false
    @State private var isCollapsed = true
    @State private var digestError: String?
    @State private var digestTask: Task<Void, Never>?

    var body: some View {
        let todaysMeetings = todaysMeetingsWithSummary
        let meetingIDs = Set(todaysMeetings.map(\.id))
        if !todaysMeetings.isEmpty || store.cachedDigest != nil {
            VStack(alignment: .leading, spacing: 0) {
                // Header — always visible
                headerView(meetings: todaysMeetings)

                // Body — collapsible
                if !isCollapsed {
                    Divider()
                    if let digest = store.cachedDigest {
                        digestContent(digest)
                            .overlay {
                                if isGenerating {
                                    regeneratingOverlay
                                }
                            }
                    } else if isGenerating {
                        loadingState
                    } else if let digestError {
                        VStack(spacing: 8) {
                            Text(digestError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            generateButton
                        }
                        .padding(.vertical, 12)
                    } else {
                        generateButton
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .fill(AppThemeConstants.surfaceBackground)
                    .shadow(color: .black.opacity(AppThemeConstants.shadowOpacityDefault), radius: AppThemeConstants.shadowRadiusDefault, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .stroke(AppThemeConstants.accent.opacity(AppThemeConstants.opacityMedium), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .onDisappear { digestTask?.cancel() }
            .task(id: meetingIDs) {
                guard await LLMEngine.shared.isModelLoaded,
                      !meetingIDs.isSubset(of: store.digestMeetingIDs)
                else { return }
                await generateDigest()
            }
        }
    }

    // MARK: - Should Show

    private var todaysMeetingsWithSummary: [MeetingNote] {
        let cal = Calendar.current
        return store.activeMeetings.filter { meeting in
            cal.isDateInToday(meeting.createdAt)
                && !meeting.isArchived && meeting.summary != nil
        }
    }

    // MARK: - Header

    private func headerView(meetings: [MeetingNote]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(AppThemeConstants.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Digest")
                    .font(.subheadline.weight(.semibold))
                if meetings.isEmpty {
                    Text("Latest digest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(meetings.count) meeting\(meetings.count == 1 ? "" : "s") today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Total duration
            let totalDuration = meetings.reduce(0.0) { $0 + $1.duration }
            if totalDuration > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(DurationFormatter.hoursMinutes(totalDuration))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            CollapseToggleButton(isCollapsed: isCollapsed) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }
            .accessibilityLabel(isCollapsed ? "Expand daily digest" : "Collapse daily digest")
        }
        .padding(AppThemeConstants.paddingLarge)
    }

    // MARK: - Digest Content

    private func digestContent(_ digest: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Headline
            Text(digest.headline)
                .font(.callout)
                .foregroundStyle(.primary)

            // Key Highlights
            if !digest.keyHighlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Key Highlights", systemImage: "star.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppThemeConstants.warning)

                    ForEach(digest.keyHighlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(AppThemeConstants.warning)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            Text(highlight)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            // Pending Actions
            if !digest.pendingActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Needs Attention", systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppThemeConstants.error)

                    ForEach(digest.pendingActions, id: \.self) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(AppThemeConstants.error.opacity(0.6))
                                .padding(.top, 4)
                            Text(action)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            // Tomorrow Focus
            if let focus = digest.tomorrowFocus, !focus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppThemeConstants.accent)
                    Text("Tomorrow: \(focus)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AppThemeConstants.accent.opacity(AppThemeConstants.hoverOpacity),
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                )
            }
        }
        .padding(AppThemeConstants.paddingLarge)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Generating your daily digest...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var regeneratingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(.ultraThinMaterial)
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Updating digest...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: 8) {
            Button {
                digestTask?.cancel()
                digestTask = Task { await generateDigest() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("Generate Digest")
                        .font(.callout.weight(.medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.accent)
            .controlSize(.small)
            .disabled(LLMEngineStatus.shared.isBusy)
            .accessibilityLabel("Generate daily digest")
            .accessibilityHint("Uses AI to summarize today's meetings into a digest")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Generation

    private func generateDigest() async {
        guard !isGenerating else { return }
        isGenerating = true

        let meetings = todaysMeetingsWithSummary
        let currentIDs = Set(meetings.map(\.id))

        if let digest = await fetchDigestFromLLM(meetings: meetings) {
            store.cachedDigest = digest
            store.digestMeetingIDs = currentIDs
            store.saveDigestCache()
            digestError = nil
        } else {
            digestError = "Digest generation failed. Tap to retry."
        }
        isGenerating = false
    }

    private func fetchDigestFromLLM(meetings: [MeetingNote]) async -> DailyDigest? {
        let meetingContext = meetings.enumerated().map { index, meeting in
            let pendingCount = meeting.actionItems.filter { !$0.isCompleted }.count
            return """
            Meeting \(index + 1): \(meeting.title)
            Summary: \(String((meeting.summary ?? "").prefix(300)))
            Action Items: \(meeting.actionItems.count) total, \(pendingCount) pending
            """
        }.joined(separator: "\n\n")

        let totalDuration = meetings.reduce(0.0) { $0 + $1.duration }
        let count = meetings.count
        let totalTime = DurationFormatter.hoursMinutes(totalDuration)
            + " across \(count) meeting\(count == 1 ? "" : "s")"

        return await withRetryOptional {
            let raw = try await LLMEngine.shared.complete(
                system: LLMEngine.chatSystemPrompt + """

                \nAnalyze today's meetings and produce a concise daily digest.
                Focus on the most important highlights and pending actions across all meetings.
                Output ONLY valid JSON with these fields:
                - "headline": one-sentence summary of the day's meetings
                - "totalMeetingTime": e.g. "2h 15m across 3 meetings"
                - "keyHighlights": array of 3-5 most important highlights
                - "pendingActions": array of top pending action items
                - "tomorrowFocus": one suggestion for what to focus on tomorrow
                No extra text before or after the JSON.
                """,
                prompt: """
                Generate a daily digest for today's meetings.

                ---

                SUMMARY:
                Total time: \(totalTime)

                <meetings>
                \(String(meetingContext.prefix(LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens))))
                </meetings>
                """
            )
            guard let digest = parseDigestJSON(raw) else { throw LLMError.emptyResponse }
            return digest
        }
    }

    private func parseDigestJSON(_ raw: String) -> DailyDigest? {
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}"),
              jsonStart <= jsonEnd,
              let data = String(raw[jsonStart ... jsonEnd]).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(DailyDigest.self, from: data)
    }
}

// MARK: - Collapse Toggle Button

private struct CollapseToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .font(.caption)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .padding(6)
                .background(
                    isHovered ? Color.primary.opacity(AppThemeConstants.opacitySubtle) : .clear,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                )
        }
        .buttonStyle(.plain)
        .overlay(HandCursorArea())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
