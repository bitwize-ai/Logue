// swiftlint:disable file_length
import SwiftUI

/// Full-screen meeting workspace: recording bar → transcript timeline → right tool panel.
/// Actions (Summarize, Start/Stop, Tag, Fav/Archive/Delete) live in the macOS toolbar.
struct MeetingWorkspaceView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(RecordingSessionManager.self) private var recorder
    // Arch-1: Use @Environment instead of SpaceStore.shared
    @Environment(SpaceStore.self) private var spaceStore

    // UI state
    @State private var activeTool: MeetingTool? = .aiChat
    @State private var newTagText = ""
    @State private var showTagPopover = false
    @FocusState private var isTagFieldFocused: Bool
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var isSidebarCollapsed = false
    @State private var toolPanelWidths: [String: CGFloat] = [:]
    @State private var scrollToSegmentID: UUID?
    @State private var audioPlaybackService = AudioPlaybackService()
    @State private var chatMessages: [MeetingChatMessage] = []
    @State private var showOnlineMeetingPrompt = false
    @State private var detectedAppName: String?
    @AppStorage("hasSeenMicSpeakerTip") private var hasSeenMicSpeakerTip = false
    @State private var showMicSpeakerTip = false

    // Bookmark state (moved from MeetingRecordingBar)
    @State private var showBookmarkPopover = false
    @State private var bookmarkLabel = ""
    @State private var bookmarkColor: BookmarkColor = .orange
    @State private var showBookmarkConfirm = false
    @State private var bookmarkConfirmTask: Task<Void, Never>?

    var body: some View {
        if let meeting = store.selectedMeeting {
            VStack(spacing: 0) {
                // Error banner
                if let errorMessage = recorder.errorMessage {
                    errorBanner(message: errorMessage)
                }

                // Space suggestion banner
                if let suggestedID = recorder.postRecordingPipeline.suggestedSpaceID,
                   recorder.postRecordingPipeline.suggestedSpaceMeetingID == meeting.id,
                   let spaceName = spaceStore.space(for: suggestedID)?.name
                {
                    spaceSuggestionBanner(
                        spaceName: spaceName,
                        meetingID: meeting.id,
                        spaceID: suggestedID
                    )
                }

                // Mic speaker tip — shown once when recording in-person without system audio
                if showMicSpeakerTip, recorder.isRecording, !recorder.isCapturingSystemAudio {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.secondary)
                        Text(
                            "Your mic may pick up audio from speakers. Use headphones or enable **System Audio** for cleaner online meeting capture."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await recorder.enableSystemAudio() }
                        } label: {
                            Text("Enable System Audio")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            withAnimation { showMicSpeakerTip = false }
                            hasSeenMicSpeakerTip = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppThemeConstants.categoryBlue.opacity(0.08))
                }

                // Main content area
                HStack(spacing: 0) {
                    // Center: transcript timeline
                    TranscriptTimelineView(
                        segments: meeting.segments,
                        volatileText: recorder.isRecording ? recorder.volatileText : "",
                        bookmarks: meeting.bookmarks,
                        isLive: recorder.isRecording,
                        externalScrollTarget: $scrollToSegmentID,
                        onAddBookmark: { timestamp, label, color in
                            let bookmark = Bookmark(label: label, timestamp: timestamp, color: color)
                            store.addBookmark(bookmark, to: meeting.id)
                        },
                        onRemoveBookmark: { bookmarkID in
                            store.removeBookmark(bookmarkID: bookmarkID, from: meeting.id)
                        },
                        onChangeBookmarkType: { bookmarkID, label, color in
                            if var bookmark = meeting.bookmarks.first(where: { $0.id == bookmarkID }) {
                                bookmark.label = label
                                bookmark.color = color
                                store.updateBookmark(bookmark, in: meeting.id)
                            }
                        },
                        onEditSegment: { segmentID, newText in
                            store.updateSegmentText(meetingID: meeting.id, segmentID: segmentID, text: newText)
                        },
                        onReassignSpeaker: { segmentID, newSpeakerLabel in
                            store.reassignSegmentSpeaker(
                                meetingID: meeting.id,
                                segmentID: segmentID,
                                newSpeakerLabel: newSpeakerLabel
                            )
                        },
                        onRenameSpeaker: { oldName, newName in
                            var updated = meeting
                            for index in updated.segments.indices where updated.segments[index].speakerLabel == oldName {
                                updated.segments[index].speakerLabel = newName
                            }
                            for index in updated.speakers.indices where updated.speakers[index].name == oldName {
                                updated.speakers[index].name = newName
                            }
                            store.updateMeeting(updated)
                        },
                        onSeekToTime: { time in
                            audioPlaybackService.seek(to: time)
                            if !audioPlaybackService.isPlaying {
                                audioPlaybackService.play()
                            }
                        },
                        activeSegmentID: audioPlaybackService.activeSegmentID,
                        speakerColors: Dictionary(
                            uniqueKeysWithValues: meeting.speakers.map { ($0.name, $0.displayColor) }
                        )
                    )
                    .frame(maxWidth: .infinity)

                    // Right: unified sidebar (tab strip + panel)
                    UnifiedSidebarView(
                        activeTool: $activeTool,
                        isCollapsed: $isSidebarCollapsed,
                        panelWidths: $toolPanelWidths
                    ) { tool in
                        rightPanel(for: tool, meeting: meeting)
                    }
                }
            }
            .background(AppThemeConstants.contentBackground)
            .navigationTitle(meeting.title)
            .navigationSubtitle(meetingSubtitle(for: meeting))
            .toolbar {
                meetingWorkspaceToolbar(for: meeting)
            }
            .id(meeting.id)
            .onAppear {
                chatMessages = meeting.chatMessages
            }
            .onChange(of: store.selectedMeetingID) { oldID, _ in
                // Save chat to the old meeting
                if let oldID {
                    store.setChatMessages(chatMessages, for: oldID)
                }
                // Load chat from the new meeting
                if let meeting = store.selectedMeeting {
                    chatMessages = meeting.chatMessages
                }
            }
            .task(id: meeting.id) {
                if store.pendingAutoRecord == meeting.id {
                    store.pendingAutoRecord = nil
                    if !recorder.isRecording {
                        await recorder.startRecording(for: meeting)
                    }
                }
            }
            .onChange(of: recorder.isRecording) { _, isRecording in
                if isRecording, !hasSeenMicSpeakerTip, !recorder.isCapturingSystemAudio {
                    withAnimation { showMicSpeakerTip = true }
                } else if !isRecording {
                    showMicSpeakerTip = false
                }
            }
            .onChange(of: recorder.isCapturingSystemAudio) { _, capturing in
                if capturing {
                    withAnimation { showMicSpeakerTip = false }
                }
            }
            .onAppear {
                audioPlaybackService.segments = meeting.segments
            }
            .onChange(of: meeting.segments) { _, newSegments in
                audioPlaybackService.segments = newSegments
            }
            .onChange(of: audioPlaybackService.activeSegmentID) { _, segmentID in
                if let segmentID {
                    scrollToSegmentID = segmentID
                }
            }
            .onDisappear {
                store.setChatMessages(chatMessages, for: meeting.id)
            }
            .onExitCommand {
                store.selectedMeetingID = nil
            }
            .onChange(of: isSidebarCollapsed) { _, collapsed in
                if !collapsed, activeTool == nil {
                    activeTool = .aiChat
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMeetingExportPanel)) { _ in
                MeetingExportPanelView.exportMarkdown(meeting: meeting)
            }
            .alert("Delete Meeting?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    store.trashMeeting(id: meeting.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(meeting.title)\" will be moved to Trash.")
            }
        }
    }
}

// MARK: - Toolbar

extension MeetingWorkspaceView {
    @ToolbarContentBuilder
    func meetingWorkspaceToolbar(for meeting: MeetingNote) -> some ToolbarContent {
        newMeetingToolbarItem()
        recordingStatusToolbarItem()
        audioToggleToolbarItems()
        recordControlToolbarItems(for: meeting)
        moreMenuToolbarItem(for: meeting)
        sidebarToggleToolbarItem()
    }

    @ToolbarContentBuilder
    func newMeetingToolbarItem() -> some ToolbarContent {
        // New meeting (left side)
        ToolbarItem(placement: .navigation) {
            Button {
                let newMeeting = store.createMeeting(
                    title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                )
                store.selectedMeetingID = newMeeting.id
            } label: {
                Image(systemName: "plus")
            }
            .help("New Meeting")
        }
    }

    @ToolbarContentBuilder
    func recordingStatusToolbarItem() -> some ToolbarContent {
        // Center: recording status when active (overrides navigationTitle)
        ToolbarItem(placement: .principal) {
            if recorder.isRecording {
                RecordingStatusView(
                    elapsedTime: recorder.elapsedTime,
                    audioLevel: recorder.audioLevel,
                    isMicActive: recorder.isMicActive,
                    isCapturingSystemAudio: recorder.isCapturingSystemAudio
                )
            }
        }
    }

    @ToolbarContentBuilder
    func audioToggleToolbarItems() -> some ToolbarContent {
        // Mic toggle (during recording)
        ToolbarItem(placement: .primaryAction) {
            if recorder.isRecording {
                Button {
                    Task { @MainActor in
                        if recorder.isMicActive {
                            recorder.disableMic()
                        } else {
                            await recorder.enableMic()
                        }
                    }
                } label: {
                    Image(systemName: recorder.isMicActive ? "mic.fill" : "mic.slash")
                        .font(.caption)
                        .foregroundStyle(recorder.isMicActive ? .primary : .secondary)
                }
                .help(recorder.isMicActive ? "Disable microphone" : "Enable microphone")
            }
        }

        // System audio toggle (during recording)
        ToolbarItem(placement: .primaryAction) {
            if recorder.isRecording {
                Button {
                    Task { @MainActor in
                        if recorder.isCapturingSystemAudio {
                            recorder.disableSystemAudio()
                        } else {
                            await recorder.enableSystemAudio()
                        }
                    }
                } label: {
                    Image(systemName: "display")
                        .font(.caption)
                        .foregroundStyle(recorder.isCapturingSystemAudio ? .primary : .tertiary)
                        .overlay {
                            if !recorder.isCapturingSystemAudio {
                                Image(systemName: "line.diagonal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .help(recorder.isCapturingSystemAudio
                    ? "Disable system audio"
                    : "Enable system audio (recommended when speakers are playing)")
            }
        }
    }

    @ToolbarContentBuilder
    func recordControlToolbarItems(for meeting: MeetingNote) -> some ToolbarContent {
        // Start/Stop
        ToolbarItem(placement: .primaryAction) {
            startStopButton(for: meeting)
        }

        // Quick bookmark (visible during recording)
        if recorder.isRecording, recorder.currentMeetingID == meeting.id {
            ToolbarItem(placement: .primaryAction) {
                quickBookmarkButton(for: meeting)
            }
        }
    }

    @ViewBuilder
    func startStopButton(for meeting: MeetingNote) -> some View {
        if recorder.isStartingRecording {
            recordProgressButton(label: "Starting…")
        } else if recorder.isStopping {
            recordProgressButton(label: "Stopping…")
        } else if recorder.isDiarizing {
            recordProgressButton(
                label: recorder.diarizationStage.isEmpty ? "Identifying speakers…" : recorder.diarizationStage
            )
        } else if recorder.isRecording {
            stopRecordingButton(for: meeting)
        } else {
            startRecordingButton(for: meeting)
        }
    }

    func recordProgressButton(label: String) -> some View {
        Button {} label: {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
            }
        }
        .disabled(true)
    }

    func stopRecordingButton(for meeting: MeetingNote) -> some View {
        Button {
            toggleRecording(for: meeting)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.circle.fill")
                Text("Stop")
            }
        }
        .tint(AppThemeConstants.error)
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityLabel("Stop recording")
        .accessibilityHint("Stops the current meeting recording")
    }

    func startRecordingButton(for meeting: MeetingNote) -> some View {
        Button {
            startSmartRecording(for: meeting)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "record.circle")
                Text("Start")
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityLabel("Start recording")
        .help("Start Recording (⌘R)")
        .alert("Online Meeting Detected", isPresented: $showOnlineMeetingPrompt) {
            Button("Capture System Audio") {
                var updated = meeting
                updated.recordingMode = .onlineMeeting
                store.updateMeeting(updated)
                toggleRecording(for: updated)
            }
            Button("Mic Only", role: .cancel) {
                var updated = meeting
                updated.recordingMode = .inPerson
                store.updateMeeting(updated)
                toggleRecording(for: updated)
            }
        } message: {
            Text("\(detectedAppName ?? "A conferencing app") is running. Capture system audio to transcribe remote speakers?")
        }
    }

    func quickBookmarkButton(for meeting: MeetingNote) -> some View {
        Button {
            let bookmark = Bookmark(label: "Bookmark", timestamp: recorder.elapsedTime, color: .orange)
            store.addBookmark(bookmark, to: meeting.id)
            showBookmarkConfirm = true
            Task { @MainActor in
                try? await Task.sleep(for: AppConstants.Delays.bookmarkConfirmLong)
                showBookmarkConfirm = false
            }
        } label: {
            Image(systemName: showBookmarkConfirm ? "bookmark.fill" : "bookmark")
                .foregroundStyle(showBookmarkConfirm ? AppThemeConstants.warning : .secondary)
        }
        .keyboardShortcut("b", modifiers: .command)
        .help("Add Bookmark (⌘B)")
        .accessibilityLabel("Add bookmark")
    }

    @ToolbarContentBuilder
    func moreMenuToolbarItem(for meeting: MeetingNote) -> some ToolbarContent {
        // More menu (right of Start/Stop)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                moreMenuContent(for: meeting)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More options")
            .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
                tagPopoverContent(meeting: meeting)
            }
            .alert("Rename Meeting", isPresented: $showRenameAlert) {
                TextField("Title", text: $renameText)
                Button("Rename") {
                    store.renameMeeting(id: meeting.id, newTitle: renameText)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    func moreMenuContent(for meeting: MeetingNote) -> some View {
        Button {
            store.togglePin(id: meeting.id)
        } label: {
            Label(
                meeting.isPinned ? "Unpin" : "Pin",
                systemImage: meeting.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            store.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        Button {
            Task { @MainActor in
                await store.regenerateAITitle(for: meeting.id)
            }
        } label: {
            Label("Generate Title", systemImage: "sparkles")
        }
        .disabled(meeting.segments.isEmpty)
        Button {
            renameText = meeting.title
            showRenameAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            showTagPopover = true
        } label: {
            Label("Add Tag", systemImage: "tag")
        }
        Divider()
        Menu {
            exportMenuContent(for: meeting)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Meeting", systemImage: "trash")
        }
    }

    @ViewBuilder
    func exportMenuContent(for meeting: MeetingNote) -> some View {
        Button {
            MeetingExportPanelView.exportTranscript(meeting: meeting)
        } label: {
            Label("Full Transcript", systemImage: "doc.text")
        }
        Button {
            MeetingExportPanelView.exportSmartMinutes(meeting: meeting)
        } label: {
            Label("Smart Minutes", systemImage: "doc.plaintext")
        }
        Button {
            MeetingExportPanelView.exportActionItems(meeting: meeting)
        } label: {
            Label("Action Items", systemImage: "checklist")
        }
        Button {
            MeetingExportPanelView.exportMarkdown(meeting: meeting)
        } label: {
            Label("Markdown", systemImage: "text.document")
        }
        if !meeting.bookmarks.isEmpty {
            Button {
                MeetingExportPanelView.exportBookmarks(meeting: meeting)
            } label: {
                Label("Bookmarked Moments", systemImage: "bookmark.fill")
            }
        }
        Divider()
        Button {
            MeetingExportPanelView.copyToClipboard(meeting.fullTranscript)
        } label: {
            Label("Copy Transcript", systemImage: "doc.on.doc")
        }
        Button {
            let content = meeting.smartMinutes != nil
                ? meeting.smartMinutesMarkdown()
                : (meeting.summary ?? "No summary available")
            MeetingExportPanelView.copyToClipboard(content)
        } label: {
            Label("Copy Summary", systemImage: "doc.on.doc")
        }
    }

    @ToolbarContentBuilder
    func sidebarToggleToolbarItem() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(isSidebarCollapsed ? "Show Tools Sidebar" : "Hide Tools Sidebar")
            .accessibilityLabel(isSidebarCollapsed ? "Show Tools Sidebar" : "Hide Tools Sidebar")
        }
    }
}

// MARK: - Helpers & Banners

extension MeetingWorkspaceView {
    func meetingSubtitle(for meeting: MeetingNote) -> String {
        var parts: [String] = []
        if meeting.duration > 0 {
            let minutes = Int(meeting.duration / 60)
            parts.append("\(minutes) min")
        }
        let segmentCount = meeting.segments.count
        if segmentCount > 0 {
            parts.append("\(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
        }
        // Count only speakers that appear in at least one transcript segment,
        // not all Speaker objects (some may have no segments assigned by diarization).
        let speakerCount = Set(meeting.segments.compactMap(\.speakerLabel)).count
        if speakerCount > 0 {
            parts.append("\(speakerCount) speaker\(speakerCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    func submitTag(to meetingID: UUID) {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addTag(trimmed, to: meetingID)
        newTagText = ""
    }

    func tagPopoverContent(meeting: MeetingNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !meeting.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(meeting.tags, id: \.self) { tag in
                        FilterChip(label: tag, style: .removable, tintColor: AppThemeConstants.tagColor(for: tag)) {
                            store.removeTag(tag, from: meeting.id)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add tag…", text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isTagFieldFocused)
                    .onSubmit { submitTag(to: meeting.id) }

                if !newTagText.isEmpty {
                    Button { submitTag(to: meeting.id) } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppThemeConstants.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add tag")
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))

            tagSuggestions(for: meeting)
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { isTagFieldFocused = true }
    }

    @ViewBuilder
    func tagSuggestions(for meeting: MeetingNote) -> some View {
        let suggestions = store.allTags.filter {
            !newTagText.isEmpty
                && $0.localizedCaseInsensitiveContains(newTagText)
                && !meeting.tags.contains($0)
        }
        if !suggestions.isEmpty {
            HStack(spacing: 4) {
                ForEach(suggestions.prefix(5), id: \.self) { suggestion in
                    let color = AppThemeConstants.tagColor(for: suggestion)
                    Button {
                        store.addTag(suggestion, to: meeting.id)
                        newTagText = ""
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(AppThemeConstants.opacityLight), in: Capsule())
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppThemeConstants.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if message.contains("permission") || message.contains("Permission") || message.contains("access denied") {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                recorder.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppThemeConstants.warning.opacity(0.08))
    }

    func spaceSuggestionBanner(spaceName: String, meetingID: UUID, spaceID: UUID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.brandPrimary)

            Text("File in")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(spaceName)
                .font(.callout.weight(.medium))

            Spacer()

            Button("Move") {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.moveMeeting(id: meetingID, toSpace: spaceID)
                    recorder.postRecordingPipeline.suggestedSpaceID = nil
                    recorder.postRecordingPipeline.suggestedSpaceMeetingID = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.accent)
            .controlSize(.small)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    recorder.postRecordingPipeline.suggestedSpaceID = nil
                    recorder.postRecordingPipeline.suggestedSpaceMeetingID = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppThemeConstants.brandPrimary.opacity(AppThemeConstants.hoverOpacity))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    func rightPanel(for tool: MeetingTool, meeting: MeetingNote) -> some View {
        switch tool {
        case .summary:
            MeetingSummaryPanelView(meeting: meeting)
        case .bookmarks:
            MeetingBookmarksPanelView(meeting: meeting, scrollToSegmentID: $scrollToSegmentID)
        case .actionItems:
            MeetingActionItemsPanelView(meeting: meeting)
        case .aiChat:
            MeetingAIChatPanelView(meeting: meeting, onSave: { saveChatMessages(meetingID: meeting.id) }, messages: $chatMessages)
        case .speakers:
            MeetingSpeakersPanelView(meeting: meeting)
        case .recording:
            AudioPlaybackView(meeting: meeting, service: audioPlaybackService)
        }
    }

    func saveChatMessages(meetingID: UUID) {
        store.setChatMessages(chatMessages, for: meetingID)
    }
}

// MARK: - Bookmarks & Recording

extension MeetingWorkspaceView {
    static let bookmarkPresets: [(String, BookmarkColor)] = [
        ("Key Decision", .blue),
        ("Action Item", .orange),
        ("Important", .red),
        ("Question", .purple),
    ]

    func addBookmark(for meeting: MeetingNote, label: String, color: BookmarkColor) {
        let bookmark = Bookmark(
            label: label,
            timestamp: recorder.elapsedTime,
            color: color
        )
        store.addBookmark(bookmark, to: meeting.id)
    }

    func bookmarkPopoverContent(meeting: MeetingNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Bookmark")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 4) {
                ForEach(Self.bookmarkPresets, id: \.0) { preset in
                    Button {
                        addBookmark(for: meeting, label: preset.0, color: preset.1)
                        showBookmarkPopover = false
                        flashBookmarkConfirm()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(preset.1.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(preset.0)
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            bookmarkCustomLabel(meeting: meeting)
        }
        .padding(12)
        .frame(width: 200)
    }

    func bookmarkCustomLabel(meeting: MeetingNote) -> some View {
        HStack(spacing: 6) {
            TextField("Custom label", text: $bookmarkLabel)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
                .onSubmit { submitBookmark(for: meeting) }

            Button { submitBookmark(for: meeting) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundColor(AppThemeConstants.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add custom bookmark")
        }
    }

    func submitBookmark(for meeting: MeetingNote) {
        addBookmark(for: meeting, label: bookmarkLabel, color: bookmarkColor)
        showBookmarkPopover = false
        bookmarkLabel = ""
        flashBookmarkConfirm()
    }

    func flashBookmarkConfirm() {
        bookmarkConfirmTask?.cancel()
        showBookmarkConfirm = true
        bookmarkConfirmTask = Task {
            try? await Task.sleep(for: AppConstants.Delays.bookmarkConfirm)
            guard !Task.isCancelled else { return }
            showBookmarkConfirm = false
        }
    }

    func toggleRecording(for meeting: MeetingNote) {
        Task { @MainActor in
            if recorder.isRecording {
                await recorder.stopRecording()
            } else {
                await recorder.startRecording(for: meeting)
            }
        }
    }

    /// Smart recording start: detects conferencing apps and prompts before choosing mode.
    private func startSmartRecording(for meeting: MeetingNote) {
        if let detected = ConferencingAppDetector.detect() {
            detectedAppName = detected.name
            showOnlineMeetingPrompt = true
        } else {
            var updated = meeting
            updated.recordingMode = .inPerson
            store.updateMeeting(updated)
            toggleRecording(for: updated)
        }
    }
}

// MARK: - Recording Status View (toolbar inline)

/// Compact recording status shown in the macOS toolbar during active recording.
struct RecordingStatusView: View {
    let elapsedTime: TimeInterval
    let audioLevel: Float
    var isMicActive: Bool = false
    var isCapturingSystemAudio: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppThemeConstants.error)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Recording")

            Text(TranscriptSegment.formatTime(elapsedTime))
                .font(.caption.monospacedDigit().weight(.medium))
                .accessibilityLabel("Recording time: \(TranscriptSegment.formatTime(elapsedTime))")

            AudioLevelMeter(level: audioLevel)
                .frame(width: 64, height: 14)

            HStack(spacing: 4) {
                if isMicActive {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if isCapturingSystemAudio {
                    Image(systemName: "display")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AppThemeConstants.error.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
    }
}
