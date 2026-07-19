import SwiftUI

/// Right panel showing the meeting summary and Smart Minutes.
struct MeetingSummaryPanelView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(RecordingSessionManager.self) private var recorder
    @Environment(DocumentStore.self) private var documentStore
    @Environment(SpaceStore.self) private var spaceStore
    @State private var narration = SummaryNarrationService.shared
    @State private var showSaveToDocSheet = false
    @State private var isGeneratingSummary = false
    @State private var generationMessage: String?
    let meeting: MeetingNote

    private var hasSummaryContent: Bool {
        meeting.smartMinutes != nil || meeting.summary != nil
    }

    private var isNarrating: Bool {
        narration.activeMeetingID == meeting.id && narration.playbackState != .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top controls bar
            if hasSummaryContent {
                topControlsBar
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if recorder.postRecordingPipeline.isGeneratingAISummary || recorder.isDiarizing {
                        aiSummaryLoadingView
                    } else if let smartMinutes = meeting.smartMinutes {
                        smartMinutesView(smartMinutes)
                    } else if let summary = meeting.summary {
                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                    } else if isGeneratingSummary {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(0.9)
                            VStack(spacing: 4) {
                                Text("Generating summary...")
                                    .font(.callout.weight(.medium))
                                Text("Using on-device AI to create Smart Minutes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        EmptyStateView(
                            icon: "sparkles",
                            title: generationMessage != nil ? "Summary generation failed" : "No summary yet",
                            description: generationMessage
                                ?? "Record a meeting and generate Smart Minutes.",
                            actionLabel: meeting.segments.isEmpty ? nil : (generationMessage != nil ? "Try Again" : "Generate Summary"),
                            action: meeting.segments.isEmpty ? nil : {
                                guard !LLMEngineStatus.shared.isBusy else { return }
                                generationMessage = nil
                                isGeneratingSummary = true
                                Task {
                                    let result = await store.generateAISummary(for: meeting.id)
                                    isGeneratingSummary = false
                                    switch result {
                                    case .success, .noActionItems:
                                        break
                                    case let .failed(error):
                                        generationMessage = "Failed to generate summary: \(error)"
                                    case .skipped:
                                        generationMessage = "AI model is not loaded. Please check Settings → Models."
                                    }
                                }
                            }
                        )
                    }

                    // Saved state card (inline, informational)
                    if hasSummaryContent, let docTitle = savedDocumentTitle {
                        savedStateCard(docTitle: docTitle)
                    }

                    // Topic Keywords
                    if !meeting.topicKeywords.isEmpty {
                        topicKeywordsSection
                    }

                    // Related Meetings
                    relatedMeetingsSection
                }
                .padding(AppThemeConstants.paddingLarge)
            }
        }
        .background(AppThemeConstants.surfaceBackground)
        .sheet(isPresented: $showSaveToDocSheet) {
            SaveSummaryToDocumentSheet(
                isPresented: $showSaveToDocSheet,
                meeting: meeting
            ) { documentID in
                var updated = meeting
                updated.summaryDocumentID = documentID
                store.updateMeeting(updated)
            }
            .environment(documentStore)
            .environment(spaceStore)
        }
    }

    // MARK: - AI Summary Loading

    private var aiSummaryLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.9)

            VStack(spacing: 4) {
                Text(recorder.isDiarizing ? "Identifying speakers..." : "Generating summary...")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Text(recorder.isDiarizing
                    ? "Analyzing audio to identify different speakers"
                    : "Using on-device AI to create Smart Minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Smart Minutes

    @ViewBuilder
    private func smartMinutesView(_ minutes: SmartMinutes) -> some View {
        // Overview paragraph
        if let summary = meeting.summary, !summary.isEmpty {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 4)
        }

        // Key Decisions
        if !minutes.keyDecisions.isEmpty {
            SummaryCard(title: "Key Decisions", icon: "checkmark.seal", accentColor: AppThemeConstants.success) {
                ForEach(Array(minutes.keyDecisions.enumerated()), id: \.offset) { _, decision in
                    BulletRow(text: decision, color: AppThemeConstants.success)
                }
            }
        }

        // Discussion Points
        if !minutes.discussionPoints.isEmpty {
            SummaryCard(title: "Discussion Points", icon: "bubble.left.and.bubble.right", accentColor: AppThemeConstants.brandPrimary) {
                ForEach(Array(minutes.discussionPoints.enumerated()), id: \.offset) { _, point in
                    BulletRow(text: point, color: AppThemeConstants.brandPrimary)
                }
            }
        }

        // Action Items
        if !minutes.actionItems.isEmpty {
            SummaryCard(title: "Action Items", icon: "checklist", accentColor: AppThemeConstants.warning) {
                ForEach(Array(minutes.actionItems.enumerated()), id: \.offset) { index, item in
                    BulletRow(text: item, color: AppThemeConstants.warning, index: index + 1)
                }
            }
        }

        // Follow-ups
        if !minutes.followUps.isEmpty {
            SummaryCard(title: "Follow-ups", icon: "arrow.uturn.forward", accentColor: AppThemeConstants.categoryPurple) {
                ForEach(Array(minutes.followUps.enumerated()), id: \.offset) { _, followUp in
                    BulletRow(text: followUp, color: AppThemeConstants.categoryPurple)
                }
            }
        }

        // Attendee Summary
        if !minutes.attendeeSummary.isEmpty {
            SummaryCard(title: "Attendees", icon: "person.2", accentColor: AppThemeConstants.accent) {
                ForEach(minutes.attendeeSummary) { attendee in
                    AttendeeRow(attendee: attendee)
                }
            }
        }
    }

    // MARK: - Top Controls Bar

    private var topControlsBar: some View {
        HStack(spacing: 8) {
            if isNarrating {
                // Playback controls
                Button { narration.skipBackward() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Previous section")

                Button { narration.togglePlayPause() } label: {
                    Image(systemName: narration.playbackState == .playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(narration.playbackState == .playing ? "Pause" : "Resume")

                Button { narration.skipForward() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Next section")

                if narration.totalSections > 1 {
                    Text("\(narration.currentSectionIndex + 1)/\(narration.totalSections)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    narration.stop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Stop narration")
            } else {
                Spacer()

                Button {
                    narration.play(meeting: meeting)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2")
                        Text("Listen")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Listen to summary")

                if savedDocumentTitle != nil {
                    Button {
                        showSaveToDocSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text("Save Again")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Save to another document")
                } else {
                    Button {
                        showSaveToDocSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)
                    .help("Save to document")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onDisappear {
            if isNarrating {
                narration.stop()
            }
        }
    }

    // MARK: - Save to Document

    /// Resolved title of the linked document, if any.
    private var savedDocumentTitle: String? {
        guard let docID = meeting.summaryDocumentID else { return nil }
        return documentStore.activeDocuments.first { $0.id == docID }?.title
    }

    private func savedStateCard(docTitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppThemeConstants.success)
            Text("Saved to")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(docTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button {
                documentStore.selectedDocumentID = meeting.summaryDocumentID
            } label: {
                Text("Open")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppThemeConstants.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(AppThemeConstants.success.opacity(AppThemeConstants.hoverOpacity))
        )
    }

    // MARK: - Topic Keywords

    private var topicKeywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Topics", icon: "tag")

            FlowLayout(spacing: 6) {
                ForEach(Array(meeting.topicKeywords.enumerated()), id: \.offset) { _, keyword in
                    FilterChip(label: keyword, style: .tinted)
                }
            }
        }
    }

    // MARK: - Related Meetings

    @ViewBuilder
    private var relatedMeetingsSection: some View {
        let related = store.relatedMeetings(to: meeting.id)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Related Meetings", icon: "link")

                ForEach(related) { relatedMeeting in
                    Button {
                        store.selectedMeetingID = relatedMeeting.id
                    } label: {
                        RelatedMeetingRow(meeting: relatedMeeting, currentKeywords: meeting.topicKeywords)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Related Meeting Row

private struct RelatedMeetingRow: View {
    let meeting: MeetingNote
    let currentKeywords: [String]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.callout)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(meeting.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Show overlapping keywords
                    let overlap = overlappingKeywords
                    if !overlap.isEmpty {
                        Text(overlap.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(AppThemeConstants.accent)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var overlappingKeywords: [String] {
        let current = Set(currentKeywords.map { $0.lowercased() })
        return meeting.topicKeywords.filter { current.contains($0.lowercased()) }
    }
}

// MARK: - Summary Card

/// Groups a section header + bullet rows in a card with accent-colored left border.
private struct SummaryCard<Content: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    /// Icon width + spacing — items indent to align with header title text.
    private static var iconWidth: CGFloat {
        14
    }

    private static var iconSpacing: CGFloat {
        6
    }

    private static var textIndent: CGFloat {
        iconWidth + iconSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: Self.iconWidth)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 10)

            // Items — indented to align with header title text
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.leading, Self.textIndent)
        }
        .padding(AppThemeConstants.paddingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: AppThemeConstants.radiusMedium,
                bottomLeadingRadius: AppThemeConstants.radiusMedium,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentColor.opacity(AppThemeConstants.opacityMuted))
            .frame(width: 3)
        }
    }
}

// MARK: - Helper Views

private struct AttendeeRow: View {
    let attendee: AttendeeContribution

    /// Icon width + spacing — key points indent to align with name text.
    private static let iconWidth: CGFloat = 16
    private static let iconSpacing: CGFloat = 6
    private static let textIndent: CGFloat = iconWidth + iconSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconWidth)
                Text(attendee.name)
                    .font(.callout.weight(.medium))
                Spacer()
                if attendee.speakingTimePercent > 0 {
                    Text("\(Int(attendee.speakingTimePercent))%")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(AppThemeConstants.opacityLight))
                        )
                }
            }
            if !attendee.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(attendee.keyPoints.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(.secondary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, Self.textIndent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
        )
    }
}
