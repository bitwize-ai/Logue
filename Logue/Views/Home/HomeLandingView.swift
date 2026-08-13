import SwiftUI

/// Everything on Home that is not the conversation: the greeting, the chips, and the
/// cards under the prompt bar.
///
/// The prompt bar itself lives in `AgentChatView`, above this view and outside its scroll
/// view. Only the cards scroll — an input bar anchored inside a scroll view moves as the
/// user scrolls, and the geometry match that slides it to the bottom on first send tears
/// when its source frame is not where the animation started.
struct HomeLandingView: View {
    /// Puts a finished sentence in the chat input without sending it.
    let onPrefill: (String) -> Void

    @Environment(DocumentStore.self) private var store
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(RecordingSessionManager.self) private var recorder

    @State private var isQuickRecording = false

    var body: some View {
        Group {
            if !isLoaded {
                ContentLoadingView()
            } else {
                cardScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppThemeConstants.paddingXXLarge) {
                if isEmpty {
                    HomeStarterCard(
                        onStartRecording: startQuickRecording,
                        onNewDocument: { _ = store.createDocument() },
                        onNewSpace: { _ = spaceStore.createSpace(name: "My Space") }
                    )
                } else {
                    stockedCards
                }
            }
            .padding(.vertical, AppThemeConstants.paddingXXLarge)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isQuickRecording {
                HomeRecordingBanner(recorder: recorder, onStopRecording: stopQuickRecording)
                Divider()
            }
        }
        .task { calendarManager.refreshUpcomingEvents() }
    }

    // MARK: - Cards

    @ViewBuilder
    private var stockedCards: some View {
        SeedDataBannerView()
        HomeAttentionCard(onStartMeeting: startMeetingFromEvent, onAsk: onPrefill)
        HomeContinueSection(onAsk: onPrefill)
        if !isQuickRecording {
            HomeQuickActions(
                onStartRecording: startQuickRecording,
                onNewMeeting: newMeeting,
                onNewDocument: { _ = store.createDocument() }
            )
        }
        DailyDigestCard()
    }

    // MARK: - State

    /// Every store this screen summarises. Greeting a returning user as a new one because
    /// their library was still being read is the loudest possible wrong answer here.
    private var isLoaded: Bool {
        store.isLoaded && meetingStore.isLoaded && spaceStore.isLoaded
    }

    private var isEmpty: Bool {
        store.activeDocuments.isEmpty
            && meetingStore.activeMeetings.isEmpty
            && spaceStore.topLevelSpaces.isEmpty
    }

    // MARK: - Actions

    private func newMeeting() {
        let meeting = meetingStore.createMeeting(
            title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        )
        meetingStore.selectedMeetingID = meeting.id
    }

    private func startQuickRecording() {
        let note = meetingStore.createVoiceNote()
        isQuickRecording = true
        Task { await recorder.startRecording(for: note) }
    }

    private func stopQuickRecording() {
        guard isQuickRecording, recorder.currentMeetingID != nil else { return }
        isQuickRecording = false
        Task { await recorder.stopRecording() }
    }

    private func startMeetingFromEvent(_ event: CalendarEvent) {
        var meeting = meetingStore.createMeeting(
            title: event.title, mode: .onlineMeeting, template: .general
        )
        meeting.calendarEventID = event.id
        meeting.scheduledStartTime = event.startDate
        meetingStore.updateMeeting(meeting)
        meetingStore.pendingAutoRecord = meeting.id
        meetingStore.selectedMeetingID = meeting.id
    }
}

// MARK: - First run

/// First run. Every card self-hides when its data is empty, so without this the landing
/// would collapse to a bare prompt box on the one day the user has least idea what to type.
struct HomeStarterCard: View {
    let onStartRecording: () -> Void
    let onNewDocument: () -> Void
    let onNewSpace: () -> Void

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: AppThemeConstants.paddingMedium) {
                CardSectionHeader(icon: "sparkles", title: "Start with one of these")

                Text("Logue gets useful the moment there is something to work from.")
                    .font(.callout)
                    .foregroundStyle(AppThemeConstants.mutedText)

                HStack(spacing: 10) {
                    HomeQuickActionButton(
                        icon: "mic.badge.plus",
                        title: "Record a meeting",
                        color: AppThemeConstants.accent,
                        action: onStartRecording
                    )
                    HomeQuickActionButton(
                        icon: "doc.badge.plus",
                        title: "Write a document",
                        color: AppThemeConstants.categoryPurple,
                        action: onNewDocument
                    )
                    HomeQuickActionButton(
                        icon: "folder.badge.plus",
                        title: "Create a space",
                        color: AppThemeConstants.success,
                        action: onNewSpace
                    )
                }
            }
        }
        .padding(.horizontal, AppThemeConstants.paddingXXLarge)
    }
}

// MARK: - Header

/// Greeting, the one-line context summary, and the chips — everything above the prompt bar.
struct HomeLandingHeader: View {
    let chips: [HomeSuggestions.Chip]
    let onPrefill: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppThemeConstants.paddingMedium) {
            Text("Good \(Self.timeOfDay)")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, AppThemeConstants.paddingXXLarge)

            HomeContextBar()

            if !chips.isEmpty {
                chipRow
            }
        }
        .padding(.top, AppThemeConstants.paddingXXLarge)
    }

    private var chipRow: some View {
        HStack(spacing: AppThemeConstants.paddingSmall) {
            ForEach(chips) { chip in
                Button {
                    onPrefill(chip.prompt)
                } label: {
                    Label(chip.label, systemImage: "sparkles")
                        .font(.callout)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Fills the prompt without sending it")
            }
            Spacer()
        }
        .padding(.horizontal, AppThemeConstants.paddingXXLarge)
    }

    static var timeOfDay: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0 ..< 12: "Morning"
        case 12 ..< 17: "Afternoon"
        default: "Evening"
        }
    }
}
