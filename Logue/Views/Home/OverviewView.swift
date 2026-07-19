import SwiftUI

// MARK: - Home View

/// Home screen — workspace landing page.
struct OverviewView: View {
    @Binding var sidebarSelection: SidebarItem?

    @Environment(DocumentStore.self) private var store
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(InsightsStatsProvider.self) private var insights
    @Environment(\.colorScheme) private var colorScheme

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(RecordingSessionManager.self) private var recorder
    @State private var isQuickRecording = false

    var body: some View {
        if isEmpty {
            welcomeState
        } else {
            mainContent
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                SeedDataBannerView()

                // 1. Context Bar
                HomeContextBar()

                // 2. Continue Where You Left Off
                HomeContinueSection()

                // 3. Needs Attention
                HomeAttentionCard(onStartMeeting: { startMeetingFromEvent($0) })

                // 4. Quick Actions
                // Note: "Your Spaces" card grid removed — spaces are already discoverable
                // in the sidebar, and this section duplicated that surface (inflating Home
                // from one screen to 1500+pt and requiring a second scroll to reach Quick
                // Actions + Daily Digest). Home now focuses on time-sensitive content.
                if !isQuickRecording {
                    HomeQuickActions(
                        onStartRecording: { startQuickRecording() },
                        onNewMeeting: {
                            let meeting = meetingStore.createMeeting(
                                title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                            )
                            meetingStore.selectedMeetingID = meeting.id
                        },
                        onNewDocument: { _ = store.createDocument() }
                    )
                }

                // 5. Daily Digest
                DailyDigestCard()
            }
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isQuickRecording {
                HomeRecordingBanner(
                    recorder: recorder,
                    onStopRecording: { stopQuickRecording() }
                )
                Divider()
            }
        }
        .task { calendarManager.refreshUpcomingEvents() }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Good \(timeOfDay)")
    }

    // MARK: - Welcome State (empty)

    private var welcomeState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Welcome to Logue")
                .font(.title2.weight(.bold))

            Text("Your workspace for meetings and documents")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button {
                    startQuickRecording()
                } label: {
                    Label("Record a Meeting", systemImage: "waveform")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.large)
                .accessibilityHint("Start a new meeting recording")

                Button {
                    _ = store.createDocument()
                } label: {
                    Label("Write a Document", systemImage: "doc.badge.plus")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Create a new blank document")

                Button {
                    if let space = spaceStore.createSpace(name: "My Space") {
                        sidebarSelection = .space(space.id)
                    }
                } label: {
                    Label("Create a Space", systemImage: "folder.badge.plus")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Create a new space to organize your work")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Good \(timeOfDay)")
    }

    // MARK: - Helpers

    private var isEmpty: Bool {
        store.activeDocuments.isEmpty
            && meetingStore.activeMeetings.isEmpty
            && spaceStore.topLevelSpaces.isEmpty
    }

    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0 ..< 12: return "Morning"
        case 12 ..< 17: return "Afternoon"
        default: return "Evening"
        }
    }

    // MARK: - Actions

    func startQuickRecording() {
        let note = meetingStore.createVoiceNote()
        isQuickRecording = true
        Task { await recorder.startRecording(for: note) }
    }

    func stopQuickRecording() {
        guard isQuickRecording, recorder.currentMeetingID != nil else { return }
        isQuickRecording = false
        Task { await recorder.stopRecording() }
    }

    func startMeetingFromEvent(_ event: CalendarEvent) {
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
