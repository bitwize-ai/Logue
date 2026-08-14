import SwiftUI

/// The cards under Home's prompt bar. The greeting and the chips are
/// `HomeLandingHeader`, and the prompt bar itself belongs to `AgentChatView` — this view
/// owns only what scrolls beneath them.
///
/// An input bar anchored inside a scroll view moves as the user scrolls, and the geometry
/// match that slides it to the bottom on first send tears when its source frame is not
/// where the animation started. That is why the bar stays outside this view.
///
/// `isLoaded` and `isEmpty` are passed in rather than derived here. `AgentChatView` gates
/// its header on the same two values, and a second definition is how the header ends up
/// answering "is this workspace empty?" differently from the cards directly beneath it.
struct HomeLandingView: View {
    let isLoaded: Bool
    let isEmpty: Bool
    /// Puts a finished sentence in the chat input without sending it.
    let onPrefill: (String) -> Void
    /// Reveals a newly created space. Creating one without opening it leaves the starter
    /// card's third button looking like it did nothing.
    let onOpenSpace: (UUID) -> Void

    @Environment(DocumentStore.self) private var store
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(RecordingSessionManager.self) private var recorder

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
                        onStartRecording: startVoiceNote,
                        onNewDocument: { _ = store.createDocument() },
                        onNewSpace: createAndOpenSpace
                    )
                } else {
                    stockedCards
                }
            }
            // The cards share the prompt bar's column instead of spanning the window.
            // The page margin lives here rather than inside each section, so every card
            // lines up on the same two edges and a new section cannot introduce a third.
            .homeContentColumn()
            .padding(.vertical, AppThemeConstants.paddingXXLarge)
        }
        .task { calendarManager.refreshUpcomingEvents() }
    }

    // MARK: - Cards

    @ViewBuilder
    private var stockedCards: some View {
        SeedDataBannerView()
        HomeAttentionCard(onStartMeeting: startMeetingFromEvent, onAsk: onPrefill)
        HomeContinueSection(onAsk: onPrefill)
        HomeQuickActions(
            onStartRecording: startVoiceNote,
            onNewMeeting: newMeeting,
            onNewDocument: { _ = store.createDocument() }
        )
        DailyDigestCard()
    }

    // MARK: - Actions

    private func newMeeting() {
        let meeting = meetingStore.createMeeting(
            title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        )
        meetingStore.selectedMeetingID = meeting.id
    }

    /// Starts recording, then lets the navigation happen. `createVoiceNote` sets
    /// `selectedMeetingID`, which `MainWindowView` turns into a jump to the meeting
    /// workspace — so the recording is watched there. Home used to carry its own banner
    /// for this, which could never appear because the jump always won.
    private func startVoiceNote() {
        let note = meetingStore.createVoiceNote()
        Task { await recorder.startRecording(for: note) }
    }

    /// `createSpace` has no selection side effect of its own, and a `nil` return reads
    /// exactly like success if it is discarded.
    private func createAndOpenSpace() {
        guard let space = spaceStore.createSpace(name: "My Space") else { return }
        onOpenSpace(space.id)
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

            HomeContextBar()

            if !chips.isEmpty {
                chipRow
            }
        }
        .homeContentColumn(alignment: .leading)
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
    }

    static var timeOfDay: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0 ..< 12: "Morning"
        case 12 ..< 17: "Afternoon"
        default: "Evening"
        }
    }
}
