import SwiftUI

// MARK: - Bookmark Chip (inline in block header)

// Extension-visible: +Bookmarks — used by SpeakerBlockView in TranscriptTimelineView.swift
struct BookmarkChip: View {
    let bookmark: Bookmark
    var onChangeType: ((UUID, String, BookmarkColor) -> Void)?
    var onRemove: ((UUID) -> Void)?
    @State private var showPopover = false

    private static let typePresets: [(label: String, color: BookmarkColor)] = [
        ("Key Decision", .blue),
        ("Action Item", .orange),
        ("Important", .red),
        ("Question", .purple),
    ]

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(bookmark.color.swiftUIColor)
                    .frame(width: 5, height: 5)
                Text(bookmark.label.isEmpty ? bookmark.formattedTimestamp : bookmark.label)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bookmark.color.swiftUIColor.opacity(AppThemeConstants.opacityLight), in: Capsule())
            .foregroundStyle(bookmark.color.swiftUIColor)
        }
        .buttonStyle(.plain)
        .help(bookmark.label.isEmpty ? "Bookmark at \(bookmark.formattedTimestamp)" : "\(bookmark.label) · \(bookmark.formattedTimestamp)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.typePresets, id: \.label) { preset in
                    Button {
                        onChangeType?(bookmark.id, preset.label, preset.color)
                        showPopover = false
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(preset.color.swiftUIColor)
                                .frame(width: 6, height: 6)
                            Text(preset.label)
                                .font(.caption)
                            Spacer()
                            if bookmark.label == preset.label {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(preset.color.swiftUIColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Button(role: .destructive) {
                    onRemove?(bookmark.id)
                    showPopover = false
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 160)
        }
    }
}

// MARK: - Block Bookmark Picker

// Extension-visible: +Bookmarks — used by SpeakerBlockView in TranscriptTimelineView.swift
struct BlockBookmarkPicker: View {
    let onAdd: (String, BookmarkColor) -> Void
    let onDismiss: () -> Void
    @State private var customLabel = ""

    private static let presets: [(String, BookmarkColor)] = [
        ("Key Decision", .blue),
        ("Action Item", .orange),
        ("Important", .red),
        ("Question", .purple),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.presets, id: \.0) { preset in
                Button {
                    onAdd(preset.0, preset.1)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(preset.1.swiftUIColor)
                            .frame(width: 8, height: 8)
                        Text(preset.0)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(BookmarkColor.yellow.swiftUIColor)
                    .frame(width: 8, height: 8)
                TextField("Custom label...", text: $customLabel)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { submitCustom() }
                Button {
                    submitCustom()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppThemeConstants.accent)
                }
                .buttonStyle(.plain)
                .disabled(customLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .padding(8)
        .frame(width: 200)
    }

    private func submitCustom() {
        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, .yellow)
        customLabel = ""
    }
}
