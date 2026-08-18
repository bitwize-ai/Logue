import AppKit
import SwiftUI

// MARK: - Speaker Block Model

// Extension-visible: used by SpeakerBlockView in TranscriptSpeakerBlockView.swift
/// A stretch of transcript shown as one block. Cut by time alone, so it may hold several speakers.
struct SpeakerBlock: Identifiable {
    let id: UUID // first segment's ID
    let speakerLabel: String?
    let startTime: TimeInterval
    let segments: [TranscriptSegment]
    let speakerColor: Color?

    var formattedStartTime: String {
        TranscriptSegment.formatTime(startTime)
    }
}

/// Scrollable transcript timeline showing segments grouped by speaker.
struct TranscriptTimelineView: View {
    let segments: [TranscriptSegment]
    var volatileText: String = ""
    var bookmarks: [Bookmark] = []
    let isLive: Bool
    @Binding var externalScrollTarget: UUID?
    var onAddBookmark: ((TimeInterval, String, BookmarkColor) -> Void)?
    var onRemoveBookmark: ((UUID) -> Void)?
    var onChangeBookmarkType: ((UUID, String, BookmarkColor) -> Void)?
    var onEditSegment: ((UUID, String) -> Void)?
    var onRenameSpeaker: ((String, String) -> Void)?
    var onSeekToTime: ((TimeInterval) -> Void)?
    var activeSegmentID: UUID?
    var speakerColors: [String: Color] = [:]
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var isNearBottom = true
    @State private var scrollTarget: UUID?
    @State private var lastVolatileScrollTime: Date = .distantPast
    @State private var cachedBlocks: [SpeakerBlock] = []
    /// Tracks (segments.count, searchText) to know when to recompute cachedBlocks.
    @State private var blockCacheKey: String = ""

    /// Cheap signature of the transcript's text, so a change that leaves the segment count alone
    /// still redraws. Hashes each id with its text — see below for why the length is not enough.
    private var segmentTextHash: Int {
        var hasher = Hasher()
        for segment in segments {
            hasher.combine(segment.id)
            // The text itself, not its length: realignment exists to swap a word for a better
            // one of similar length, and a length-only hash calls that no change at all.
            hasher.combine(segment.text)
        }
        return hasher.finalize()
    }

    /// Hash of all speaker labels — changes when segments are reassigned to different speakers.
    private var speakerLabelHash: Int {
        segments.reduce(0) { $0 ^ ($1.speakerLabel?.hashValue ?? 0) }
    }

    private var filteredSegments: [TranscriptSegment] {
        guard !searchText.isEmpty else { return segments }
        return segments.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
                || ($0.speakerLabel?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Groups consecutive segments by speaker. Starts a new block when the speaker changes
    /// or there's a >15s gap between segments from the same speaker.
    /// Segments without a speaker label merge into the previous block to avoid orphan cards.
    private func computeSpeakerBlocks() -> [SpeakerBlock] {
        var blocks: [SpeakerBlock] = []
        var currentSegments: [TranscriptSegment] = []
        var currentSpeaker: String?
        var blockStart: TimeInterval = 0

        for segment in filteredSegments {
            // Blocks are decided by time alone. Splitting on the speaker as well meant the whole
            // transcript was re-cut the moment diarization finished — a different number of blocks,
            // content merged and split, and the reader's place lost. Who is speaking is now shown in
            // the gutter instead, so identifying speakers adds labels without moving anything.
            let timeGap = !currentSegments.isEmpty
                && (segment.startTime - (currentSegments.last?.endTime ?? 0)) > 15

            if timeGap {
                if !currentSegments.isEmpty {
                    blocks.append(SpeakerBlock(
                        id: currentSegments[0].id,
                        speakerLabel: currentSpeaker,
                        startTime: blockStart,
                        segments: currentSegments,
                        speakerColor: speakerColors[currentSpeaker ?? ""]
                    ))
                }
                currentSegments = [segment]
                currentSpeaker = segment.speakerLabel
                blockStart = segment.startTime
            } else {
                currentSegments.append(segment)
            }
        }

        if !currentSegments.isEmpty {
            blocks.append(SpeakerBlock(
                id: currentSegments[0].id,
                speakerLabel: currentSpeaker,
                startTime: blockStart,
                segments: currentSegments,
                speakerColor: speakerColors[currentSpeaker ?? ""]
            ))
        }

        return blocks
    }

    /// Maps bookmarks to the block whose start time is closest to (and ≤) the bookmark timestamp.
    private func buildBookmarkMap(for blocks: [SpeakerBlock]) -> [UUID: [Bookmark]] {
        var map: [UUID: [Bookmark]] = [:]
        for bookmark in bookmarks {
            var targetBlock = blocks.first
            for block in blocks {
                if block.startTime <= bookmark.timestamp {
                    targetBlock = block
                } else {
                    break
                }
            }
            if let id = targetBlock?.id {
                map[id, default: []].append(bookmark)
            }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBarField(text: $searchText, placeholder: "Search transcript", expandable: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if segments.isEmpty {
                emptyState
            } else if filteredSegments.isEmpty {
                searchEmptyState
            } else {
                let blocks = cachedBlocks
                let bookmarkMap = buildBookmarkMap(for: blocks)
                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                                    let isLastBlock = index == blocks.count - 1
                                    SpeakerBlockView(
                                        block: block,
                                        blockBookmarks: bookmarkMap[block.id] ?? [],
                                        searchText: searchText,
                                        volatileText: isLastBlock ? volatileText : "",
                                        onAddBookmark: onAddBookmark,
                                        onRemoveBookmark: onRemoveBookmark,
                                        onChangeBookmarkType: onChangeBookmarkType,
                                        onEditSegment: onEditSegment,
                                        onRenameSpeaker: onRenameSpeaker,
                                        onSeekToTime: onSeekToTime,
                                        activeSegmentID: activeSegmentID,
                                        speakerColors: speakerColors
                                    )
                                }

                                // Volatile text when no blocks exist yet (very start of recording)
                                if blocks.isEmpty, !volatileText.isEmpty {
                                    volatileTextBlock
                                }

                                // Invisible anchor at the bottom for scroll detection
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom-anchor")
                                    .onAppear { isNearBottom = true }
                                    .onDisappear { isNearBottom = false }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .onChange(of: segments.count) {
                            if isLive, isNearBottom, let lastID = segments.last?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: volatileText) {
                            if isLive, isNearBottom, !volatileText.isEmpty {
                                let now = Date()
                                guard now.timeIntervalSince(lastVolatileScrollTime) > 0.3 else { return }
                                lastVolatileScrollTime = now
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo("volatile-text", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: scrollTarget) { _, target in
                            if let target {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                                scrollTarget = nil
                            }
                        }
                        .onChange(of: externalScrollTarget) { _, target in
                            if let target {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                                externalScrollTarget = nil
                            }
                        }
                        // Playback following — auto-scroll to the active segment so the user
                        // can always see which line is currently being played back.
                        // Skipped during live recording (that path has its own scroll logic).
                        .onChange(of: activeSegmentID) { _, newID in
                            guard !isLive, let id = newID else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }

                        // Floating "Jump to latest" button
                        if isLive, !isNearBottom {
                            Button {
                                if let lastID = segments.last?.id {
                                    withAnimation {
                                        proxy.scrollTo(lastID, anchor: .bottom)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .font(.caption2.weight(.bold))
                                    Text("Jump to latest")
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(Color.primary.opacity(AppThemeConstants.opacityLight), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(AppThemeConstants.contentBackground)
        .onAppear { recomputeBlocksIfNeeded() }
        .onChange(of: segments.count) { recomputeBlocksIfNeeded() }
        // Text changing without the count changing is the ordinary case during recording, not an
        // edge one: a continuation folded into the line before it by `TranscriptSentenceMerge`
        // leaves the count alone, and realignment swaps words for better ones. Without this the
        // key that discriminates on text was never re-evaluated, so the transcript stopped
        // updating mid-recording — the defect this view's cache key was widened for.
        .onChange(of: segmentTextHash) { recomputeBlocksIfNeeded() }
        .onChange(of: searchText) { recomputeBlocksIfNeeded() }
        .onChange(of: speakerColors) { forceRecomputeBlocks() }
        .onChange(of: speakerLabelHash) { forceRecomputeBlocks() }
    }

    private func recomputeBlocksIfNeeded() {
        // Includes a signature of the text, not just the count. Merging a continuation into the
        // line before it leaves the count unchanged, and realignment rewrites text without touching
        // the count at all — both were invisible to a key built from counts alone, so the transcript
        // stopped updating mid-recording.
        let key = "\(segments.count)|\(searchText)|\(speakerLabelHash)|\(segmentTextHash)"
        guard key != blockCacheKey else { return }
        blockCacheKey = key
        cachedBlocks = computeSpeakerBlocks()
    }

    /// Force recompute blocks — used when speaker names/colors change (cache key may not detect name changes).
    private func forceRecomputeBlocks() {
        blockCacheKey = ""
        cachedBlocks = computeSpeakerBlocks()
    }

    // MARK: - Volatile Text Block

    private var volatileTextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppThemeConstants.error)
                    .frame(width: 6, height: 6)
                    .opacity(0.8)
                Text("Live")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppThemeConstants.error.opacity(0.8))
            }

            Text(volatileText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
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
            .fill(AppThemeConstants.error.opacity(AppThemeConstants.opacityMedium))
            .frame(width: 3)
        }
        .id("volatile-text")
        .transition(.opacity)
    }

    // MARK: - Empty States

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No matches found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try a different search term.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if isLive {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Listening...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Transcript will appear here as you speak.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("No transcript")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Speaker Block View

// Renders a group of consecutive segments from the same speaker as a card.

// MARK: - Shared Highlight Utility

/// Creates an AttributedString with search query matches highlighted.
func highlightedText(_ text: String, query: String, baseFont: Font = .body) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.font = baseFont
    guard !query.isEmpty else { return attributed }
    var searchRange = attributed.startIndex
    while searchRange < attributed.endIndex,
          let range = attributed[searchRange...].range(of: query, options: .caseInsensitive)
    {
        attributed[range].backgroundColor = AppThemeConstants.warning.opacity(0.3)
        attributed[range].font = baseFont.bold()
        searchRange = range.upperBound
    }
    return attributed
}

// MARK: - Segment Text Row (within a block)

// Extension-visible: used by SpeakerBlockView in TranscriptSpeakerBlockView.swift
/// Renders a single segment's text within a speaker block. Supports double-click editing.
struct SegmentTextRow: View {
    let segment: TranscriptSegment
    var searchText: String = ""
    var onEditSegment: ((UUID, String) -> Void)?
    var onSeekToTime: ((TimeInterval) -> Void)?
    var isActive: Bool = false
    var isDraggable: Bool = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isRowHovered = false
    @FocusState private var isEditFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isEditing {
                TextField("", text: $editText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1 ... 10)
                    .focused($isEditFocused)
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppThemeConstants.accent.opacity(AppThemeConstants.hoverOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppThemeConstants.accent.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear { isEditFocused = true }
                    .onChange(of: isEditFocused) { _, focused in
                        if !focused {
                            commitEdit()
                        }
                    }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    // Playback position dot — white on active (sits on blue bg), accent on hover
                    if isActive {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                            .transition(.scale.combined(with: .opacity))
                    } else if isDraggable, isRowHovered {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }

                    Text(highlightedText(segment.text, query: searchText))
                        .lineSpacing(2)
                        .foregroundStyle(isActive ? Color.white : Color.primary)
                        .fontWeight(isActive ? .medium : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, isActive ? 10 : ((isDraggable && isRowHovered) ? 4 : 0))
                .padding(.vertical, isActive ? 5 : ((isDraggable && isRowHovered) ? 2 : 0))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive
                            ? AppThemeConstants.accent.opacity(0.88)
                            : (isDraggable && isRowHovered
                                ? Color.primary.opacity(AppThemeConstants.opacitySubtle)
                                : Color.clear))
                )
                .onHover { isRowHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: isRowHovered)
                .animation(.easeInOut(duration: 0.25), value: isActive)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if onEditSegment != nil {
                        editText = segment.text
                        isEditing = true
                    }
                }
                .contextMenu {
                    if let onSeekToTime {
                        Button {
                            onSeekToTime(segment.startTime)
                        } label: {
                            Label("Play from here", systemImage: "play.fill")
                        }
                        Divider()
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(segment.text, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if onEditSegment != nil {
                        Button {
                            editText = segment.text
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
                .help(isDraggable ? "Drag to move, double-click to edit" : (onEditSegment != nil ? "Double-click to edit" : ""))
            }

            if segment.confidence < 0.7 {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(AppThemeConstants.warning)
                    .help("Low confidence transcription")
                    .accessibilityLabel("Low confidence transcription")
            }
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != segment.text {
            onEditSegment?(segment.id, trimmed)
        }
        isEditing = false
    }
}
