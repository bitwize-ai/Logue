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
    /// The paragraph the pointer is in, if any.
    @State private var hoveredGroupID: UUID?
    /// The line whose bookmark picker is open.
    ///
    /// An identity rather than a flag: every marked line attaches a popover, and binding them all
    /// to one boolean made SwiftUI anchor the picker to whichever button happened to render last —
    /// so it opened at the bottom of the transcript instead of beside the button pressed.
    @State private var bookmarkingSegmentID: UUID?
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

    // What the gutter shows for a line, given that unmarked lines normally show nothing.
    //
    // Hovering a block of mixed speakers reveals every line's speaker rather than only the ones
    // that open a turn — so an exchange can be read attributed without anything moving, and
    // without carrying that weight all the time.

    /// One paragraph: its lines, its bookmark chips, and the affordance to add another.
    ///
    /// Hover is tracked here rather than on the block, so the bookmark button stays reachable while
    /// the pointer is anywhere in the paragraph it belongs to.
    @ViewBuilder
    private func groupView(_ group: TimestampGroup, isFirst: Bool) -> some View {
        let isGroupHovered = hoveredGroupID == group.id
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(group.segments.enumerated()), id: \.element.id) { index, segment in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    gutterColumn(
                        for: segment,
                        mark: index == 0 ? group.mark : nil,
                        revealSpeaker: isGroupHovered && group.holdsSeveralSpeakers
                    )

                    SegmentTextRow(
                        segment: segment,
                        searchText: searchText,
                        onEditSegment: onEditSegment,
                        onSeekToTime: onSeekToTime,
                        isActive: activeSegmentID == segment.id,
                        isDraggable: false
                    )

                    if index == 0 {
                        bookmarkButton(for: segment)
                            .opacity(isGroupHovered ? 1 : 0)
                    }
                }
                .id(segment.id)
            }

            ForEach(bookmarks(for: group)) { bookmark in
                BookmarkChip(bookmark: bookmark, onChangeType: onChangeBookmarkType, onRemove: onRemoveBookmark)
                    .padding(.leading, 71)
            }
        }
        // A paragraph gets air above it, so the gutter marks a boundary the text also shows.
        .padding(.top, isFirst ? 0 : 10)
        .contentShape(Rectangle())
        .onHover { hoveredGroupID = $0 ? group.id : nil }
    }

    /// Which bookmarks belong beside a given line.
    ///
    /// A bookmark belongs to the marked line it falls at or after — the same moment the gutter
    /// names — so it sits with the words it was placed against instead of at the top of everything.
    private func bookmarks(for group: TimestampGroup) -> [Bookmark] {
        let start = group.segments.first?.startTime ?? 0
        let nextStart = timestampGroups
            .drop { $0.id != group.id }
            .dropFirst()
            .first?
            .segments.first?.startTime

        return blockBookmarks.filter { bookmark in
            guard bookmark.timestamp >= start else { return false }
            guard let nextStart else { return true }
            return bookmark.timestamp < nextStart
        }
    }

    /// Adds a bookmark at this line's moment. Revealed on hover, like the rest of the chrome.
    @ViewBuilder
    private func bookmarkButton(for segment: TranscriptSegment) -> some View {
        if onAddBookmark != nil {
            Button {
                bookmarkingSegmentID = segment.id
            } label: {
                Image(systemName: "bookmark")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add bookmark at \(TranscriptSegment.formatTime(segment.startTime))")
            .help("Add bookmark here")
            .popover(
                isPresented: Binding(
                    get: { bookmarkingSegmentID == segment.id },
                    set: { presented in
                        if !presented, bookmarkingSegmentID == segment.id {
                            bookmarkingSegmentID = nil
                        }
                    }
                ),
                arrowEdge: .trailing
            ) {
                bookmarkPicker(for: segment)
            }
        }
    }

    /// The left-hand column: who is speaking, then when.
    @ViewBuilder
    private func gutterColumn(
        for segment: TranscriptSegment,
        mark: TranscriptGutter.Mark?,
        revealSpeaker: Bool
    ) -> some View {
        let shown = gutterSpeaker(for: segment, mark: mark, revealSpeaker: revealSpeaker)
        let speakerToken = shown?.0 ?? ""
        let speakerName = shown?.1 ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(speakerToken)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(speakerColor(for: shown?.1) ?? Color.secondary)
                .opacity(mark == nil ? 0.55 : 1)
                .frame(width: 22, alignment: .trailing)
                .help(speakerName.isEmpty ? "" : "\(speakerName) — right-click to rename")
                .contextMenu {
                    if onRenameSpeaker != nil, !speakerName.isEmpty {
                        Button {
                            speakerNameDraft = speakerName
                            isEditingSpeakerName = true
                        } label: {
                            Label("Rename Speaker", systemImage: "pencil")
                        }
                    }
                }
            Text(mark?.time ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(mark == nil)
    }

    private func gutterSpeaker(
        for segment: TranscriptSegment,
        mark: TranscriptGutter.Mark?,
        revealSpeaker: Bool
    ) -> (String, String)? {
        if let mark, !mark.shortSpeaker.isEmpty {
            return (mark.shortSpeaker, mark.speaker ?? "")
        }
        // Only where a paragraph actually holds an exchange. Elsewhere the name at the top of the
        // paragraph already says who is talking, and repeating it on every line is noise.
        guard revealSpeaker, let label = segment.speakerLabel else { return nil }
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

    /// A run of lines under one gutter mark — what a reader sees as a paragraph.
    ///
    /// The unit that matters for hovering and for bookmarking. Blocks are cut by time, so
    /// continuous speech makes exactly one of them, and anything scoped to a block is really scoped
    /// to the whole transcript.
    private struct TimestampGroup: Identifiable {
        let id: UUID
        let mark: TranscriptGutter.Mark
        var segments: [TranscriptSegment]

        /// Whether this group needs its lines attributed individually.
        var holdsSeveralSpeakers: Bool {
            var seen: Set<String> = []
            for label in segments.compactMap(\.speakerLabel) {
                seen.insert(label)
            }
            return seen.count > 1
        }
    }

    private var timestampGroups: [TimestampGroup] {
        let marks = gutterMarks
        var groups: [TimestampGroup] = []
        for segment in block.segments {
            if let mark = marks[segment.id] {
                groups.append(TimestampGroup(id: segment.id, mark: mark, segments: [segment]))
            } else if !groups.isEmpty {
                groups[groups.count - 1].segments.append(segment)
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isEditingSpeakerName {
                header
                    .padding(.leading, 71)
            }

            ForEach(Array(timestampGroups.enumerated()), id: \.element.id) { index, group in
                groupView(group, isFirst: index == 0)
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
                    // Styled exactly as a finalised line so that when the transcriber commits it,
                    // the text does not visibly change.
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

    private func bookmarkPicker(for segment: TranscriptSegment) -> some View {
        BlockBookmarkPicker(
            onAdd: { label, color in
                // The moment the button sits beside, not the block's start — blocks are cut by
                // time, so that was the beginning of the transcript.
                onAddBookmark?(segment.startTime, label, color)
                bookmarkingSegmentID = nil
                showBookmarkAdded = true
                Task {
                    try? await Task.sleep(for: AppConstants.Delays.bookmarkConfirm)
                    showBookmarkAdded = false
                }
            },
            onDismiss: { bookmarkingSegmentID = nil }
        )
    }
}
