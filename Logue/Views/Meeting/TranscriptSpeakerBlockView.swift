import AppKit
import SwiftUI

/// One block of transcript: a stretch of lines with a gutter carrying who spoke and when.
///
/// Split out of `TranscriptTimelineView` to keep that file within its length limit. Blocks are cut
/// by time alone, so a single block can hold an exchange between several speakers — which is why
/// the gutter, rather than the block itself, carries speaker identity.
struct SpeakerBlockView: View {
    let block: SpeakerBlock
    var blockBookmarks: [Bookmark] = []
    var searchText: String = ""
    var volatileText: String = ""
    var onAddBookmark: ((TimeInterval, String, BookmarkColor) -> Void)?
    var onRemoveBookmark: ((UUID) -> Void)?
    var onChangeBookmarkType: ((UUID, String, BookmarkColor) -> Void)?
    var onEditSegment: ((UUID, String) -> Void)?
    var onRenameSpeaker: ((String, String) -> Void)?
    var onSeekToTime: ((TimeInterval) -> Void)?
    var activeSegmentID: UUID?
    var speakerColors: [String: Color] = [:]
    @State private var isHovered = false
    @State private var showBookmarkPopover = false
    /// The moment the open bookmark picker will attach to.
    @State private var bookmarkTarget: TimeInterval?
    @State private var showBookmarkAdded = false
    @State private var isEditingSpeakerName = false
    @State private var speakerNameDraft = ""
    @FocusState private var isSpeakerNameFocused: Bool

    /// Accent color for the left border — speaker color or a default.
    private var accentColor: Color {
        block.speakerColor ?? AppThemeConstants.mutedText
    }

    /// True when one of this block's segments is the currently playing line.
    private var containsActiveSegment: Bool {
        guard let activeID = activeSegmentID else { return false }
        return block.segments.contains { $0.id == activeID }
    }

    /// Which segments print a time in the left gutter, and what it says.
    ///
    /// One per stretch of the meeting rather than one per sentence. A timestamp against every line
    /// is noise — the gutter exists so someone can scan for roughly when something was said, and a
    /// column of near-identical numbers makes that harder, not easier. Segments in between are
    /// blank, so a run of sentences reads as a paragraph belonging to the time above it.
    private var gutterMarks: [UUID: TranscriptGutter.Mark] {
        TranscriptGutter.marks(for: block.segments)
    }

    /// The distinct speakers this block covers. Blocks are cut by time now, not by speaker, so one
    /// can hold a whole exchange.
    private var blockSpeakers: [String] {
        var seen: [String] = []
        for label in block.segments.compactMap(\.speakerLabel) where !seen.contains(label) {
            seen.append(label)
        }
        return seen
    }

    /// Only worth disambiguating line by line when the block actually holds more than one voice.
    private var holdsSeveralSpeakers: Bool {
        blockSpeakers.count > 1
    }

    // What the gutter shows for a line, given that unmarked lines normally show nothing.
    //
    // Hovering a block of mixed speakers reveals every line's speaker rather than only the ones
    // that open a turn — so an exchange can be read attributed without anything moving, and
    // without carrying that weight all the time.

    /// Which bookmarks belong beside a given line.
    ///
    /// A bookmark belongs to the marked line it falls at or after — the same moment the gutter
    /// names — so it sits with the words it was placed against instead of at the top of everything.
    private func bookmarks(for segment: TranscriptSegment) -> [Bookmark] {
        let marks = gutterMarks
        guard marks[segment.id] != nil else { return [] }

        let markedTimes = block.segments
            .filter { marks[$0.id] != nil }
            .map(\.startTime)
            .sorted()
        let nextMark = markedTimes.first { $0 > segment.startTime }

        return blockBookmarks.filter { bookmark in
            guard bookmark.timestamp >= segment.startTime else { return false }
            guard let nextMark else { return true }
            return bookmark.timestamp < nextMark
        }
    }

    /// Adds a bookmark at this line's moment. Revealed on hover, like the rest of the chrome.
    @ViewBuilder
    private func bookmarkButton(for segment: TranscriptSegment) -> some View {
        if onAddBookmark != nil {
            Button {
                bookmarkTarget = segment.startTime
                showBookmarkPopover = true
            } label: {
                Image(systemName: "bookmark")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add bookmark at \(TranscriptSegment.formatTime(segment.startTime))")
            .help("Add bookmark here")
            .opacity(isHovered ? 1 : 0)
            .popover(isPresented: $showBookmarkPopover, arrowEdge: .trailing) {
                bookmarkTypePicker
            }
        }
    }

    /// The left-hand column: who is speaking, then when.
    @ViewBuilder
    private func gutterColumn(for segment: TranscriptSegment, mark: TranscriptGutter.Mark?) -> some View {
        let shown = gutterSpeaker(for: segment, mark: mark)
        let speakerToken = shown?.0 ?? ""
        let speakerName = shown?.1 ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(speakerToken)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(speakerColor(for: shown?.1) ?? Color.secondary)
                .opacity(mark == nil ? 0.55 : 1)
                .frame(width: 22, alignment: .trailing)
                .help(speakerName)
            Text(mark?.time ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(mark == nil)
    }

    private func gutterSpeaker(for segment: TranscriptSegment, mark: TranscriptGutter.Mark?) -> (String, String)? {
        if let mark, !mark.shortSpeaker.isEmpty {
            return (mark.shortSpeaker, mark.speaker ?? "")
        }
        guard isHovered, holdsSeveralSpeakers, let label = segment.speakerLabel else { return nil }
        return (SpeakerShortLabel.forSpeaker(label), label)
    }

    private func speakerColor(for speaker: String?) -> Color? {
        guard let speaker else { return nil }
        return speakerColors[speaker]
    }

    /// Speaker name and any bookmark chips. Never the block's time — the gutter prints that.
    private var header: some View {
        HStack(spacing: 6) {
            if let speaker = block.speakerLabel {
                if isEditingSpeakerName {
                    TextField("Speaker name", text: $speakerNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: 160)
                        .focused($isSpeakerNameFocused)
                        .onSubmit { commitSpeakerRename(oldName: speaker) }
                        .onExitCommand { isEditingSpeakerName = false }
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                isSpeakerNameFocused = true
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                            }
                        }
                        .onChange(of: isSpeakerNameFocused) { _, focused in
                            if !focused {
                                commitSpeakerRename(oldName: speaker)
                            }
                        }

                    Button("Done") { commitSpeakerRename(oldName: speaker) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("Cancel") { isEditingSpeakerName = false }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    Text(highlightedText(speaker, query: searchText, baseFont: .caption.weight(.semibold)))
                        .foregroundColor(accentColor)
                        .onTapGesture(count: 2) {
                            if onRenameSpeaker != nil {
                                speakerNameDraft = speaker
                                isEditingSpeakerName = true
                            }
                        }
                        .help(onRenameSpeaker != nil ? "Double-click to rename speaker" : "")
                        .contextMenu {
                            if onRenameSpeaker != nil {
                                Button {
                                    speakerNameDraft = speaker
                                    isEditingSpeakerName = true
                                } label: {
                                    Label("Rename Speaker", systemImage: "pencil")
                                }
                            }
                        }
                }
            }

            // No timestamp here: the gutter prints the block's start time on its first line,
            // and two copies of it an inch apart is just noise.

            // Inline bookmark chips
            ForEach(blockBookmarks) { bookmark in
                BookmarkChip(bookmark: bookmark, onChangeType: onChangeBookmarkType, onRemove: onRemoveBookmark)
            }

            Spacer()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Only rendered when there is something in it. Before diarization has named anyone a
            // block has no speaker and usually no bookmarks, and an empty row holding a single
            // floating button is worse than no row.
            // Segment text — only first/last lines are draggable (boundary lines)
            VStack(alignment: .leading, spacing: 5) {
                let segmentCount = block.segments.count
                let gutter = gutterMarks
                ForEach(Array(block.segments.enumerated()), id: \.element.id) { index, segment in
                    let mark = gutter[segment.id]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Blank for most lines, so a run of sentences reads as one paragraph
                            // under the mark that opened it rather than a stack of stamped lines.
                            gutterColumn(for: segment, mark: mark)

                            SegmentTextRow(
                                segment: segment,
                                searchText: searchText,
                                onEditSegment: onEditSegment,
                                onSeekToTime: onSeekToTime,
                                isActive: activeSegmentID == segment.id,
                                isDraggable: false
                            )

                            // Bookmarking belongs to a moment, and the gutter mark is what names
                            // one. On the block it was effectively on the whole transcript, since
                            // blocks are cut by time and continuous speech makes just one.
                            if mark != nil {
                                bookmarkButton(for: segment)
                            }
                        }

                        ForEach(bookmarks(for: segment)) { bookmark in
                            BookmarkChip(
                                bookmark: bookmark,
                                onChangeType: onChangeBookmarkType,
                                onRemove: onRemoveBookmark
                            )
                            .padding(.leading, 71)
                        }
                    }
                    // A stamped line starts a new group, so it gets air above it. Without this the
                    // gutter marks a boundary the text gives no sign of.
                    .padding(.top, mark != nil && index > 0 ? 10 : 0)
                    .id(segment.id)
                }

                // Volatile text — in-progress transcription appended to last block
                if !volatileText.isEmpty {
                    HStack(spacing: 6) {
                        // Sits in the gutter so the text it precedes lines up with every other line.
                        Circle()
                            .fill(AppThemeConstants.error)
                            .frame(width: 5, height: 5)
                            .opacity(0.8)
                            .frame(width: 61, alignment: .trailing)
                            .padding(.trailing, 4)
                        // Styled exactly as a finalised line — same font, weight, colour and line
                        // spacing — so that when the transcriber commits it, the text does not
                        // visibly change. The dot in the gutter is what says it is still in flight.
                        Text(volatileText)
                            .font(.body)
                            .lineSpacing(2)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id("volatile-text")
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Filled only when the block is saying something about itself — being dropped onto, playing
        // back, or under the pointer. At rest it is the page, so a transcript reads as a document
        // rather than as a stack of tiles.
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(containsActiveSegment ? accentColor.opacity(0.09) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .stroke(
                    accentColor.opacity(containsActiveSegment ? 0.45 : 0),
                    lineWidth: containsActiveSegment ? 1.5 : 2
                )
        )
        .animation(.easeInOut(duration: 0.25), value: containsActiveSegment)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Speaker Rename

    private func commitSpeakerRename(oldName: String) {
        let trimmed = speakerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != oldName {
            onRenameSpeaker?(oldName, trimmed)
        }
        isEditingSpeakerName = false
    }

    // MARK: - Bookmark Picker

    private var bookmarkTypePicker: some View {
        BlockBookmarkPicker(
            onAdd: { label, color in
                // The moment the user pressed the button beside, not the block's start — with
                // blocks cut by time, that was the beginning of the transcript.
                onAddBookmark?(bookmarkTarget ?? block.startTime, label, color)
                showBookmarkPopover = false
                showBookmarkAdded = true
                Task {
                    try? await Task.sleep(for: AppConstants.Delays.bookmarkConfirm)
                    showBookmarkAdded = false
                }
            },
            onDismiss: { showBookmarkPopover = false }
        )
    }
}
