import SwiftUI

/// Right panel showing speaker information and contributions.
struct MeetingSpeakersPanelView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(RecordingSessionManager.self) private var recorder
    let meeting: MeetingNote

    @State private var editingSpeaker: String?
    @State private var newName = ""

    var body: some View {
        Group {
            if recorder.isDiarizing {
                diarizationLoadingView
            } else if speakerStats.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No speakers detected",
                    description: "Speaker labels are assigned during transcription based on audio patterns.",
                    actionLabel: meeting.segments.isEmpty && !recorder.isRecording && !recorder.isStartingRecording ? "Start Meeting" : nil,
                    action: meeting.segments.isEmpty && !recorder.isRecording && !recorder.isStartingRecording ? {
                        Task { await recorder.startRecording(for: meeting) }
                    } : nil
                )
            } else {
                List {
                    Section {
                        ForEach(speakerStats, id: \.name) { stat in
                            SpeakerRow(
                                stat: stat,
                                isEditing: editingSpeaker == stat.name,
                                newName: $newName,
                                onStartEdit: {
                                    editingSpeaker = stat.name
                                    newName = stat.name
                                },
                                onCommitEdit: {
                                    renameSpeaker(from: stat.name, to: newName)
                                    editingSpeaker = nil
                                },
                                onCancelEdit: {
                                    editingSpeaker = nil
                                }
                            )
                            .listRowSeparator(.visible)
                        }
                    } header: {
                        Text("\(speakerStats.count) speakers")
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Diarization Loading

    private var diarizationLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.9)

            VStack(spacing: 4) {
                Text("Identifying speakers...")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Text("Analyzing audio patterns to detect speakers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Speaker Stats

    struct SpeakerStat {
        let name: String
        let segmentCount: Int
        let totalDuration: TimeInterval
        let percentage: Double
    }

    private var speakerStats: [SpeakerStat] {
        var stats: [String: (count: Int, duration: TimeInterval)] = [:]
        let totalDuration = meeting.segments.reduce(0.0) { $0 + $1.duration }

        for segment in meeting.segments {
            let speaker = segment.speakerLabel ?? "Unknown"
            let existing = stats[speaker, default: (count: 0, duration: 0)]
            stats[speaker] = (count: existing.count + 1, duration: existing.duration + segment.duration)
        }

        return stats.map { name, data in
            SpeakerStat(
                name: name,
                segmentCount: data.count,
                totalDuration: data.duration,
                percentage: totalDuration > 0 ? (data.duration / totalDuration) * 100 : 0
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    // MARK: - Rename

    private func renameSpeaker(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }

        var updated = meeting

        for index in updated.segments.indices where updated.segments[index].speakerLabel == oldName {
            updated.segments[index].speakerLabel = trimmed
        }

        for index in updated.speakers.indices where updated.speakers[index].name == oldName {
            updated.speakers[index].name = trimmed
        }

        store.updateMeeting(updated)
    }
}

// MARK: - Speaker Row

private struct SpeakerRow: View {
    let stat: MeetingSpeakersPanelView.SpeakerStat
    let isEditing: Bool
    @Binding var newName: String
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)

                if isEditing {
                    TextField("Speaker name", text: $newName, onCommit: onCommitEdit)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .focused($isFieldFocused)
                        // A21: Replaced DispatchQueue.main.asyncAfter with Task.sleep
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                isFieldFocused = true
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                            }
                        }

                    Button("Done", action: onCommitEdit)
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("Cancel", action: onCancelEdit)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    Text(stat.name)
                        .font(.callout.weight(.medium))
                        .onTapGesture(count: 2, perform: onStartEdit)
                        .help("Double-click to rename")
                        .accessibilityLabel("Speaker \(stat.name)")
                        .accessibilityHint("Double-tap to rename")
                        .contextMenu {
                            Button {
                                onStartEdit()
                            } label: {
                                Label("Rename Speaker", systemImage: "pencil")
                            }
                        }

                    Spacer()

                    Text("\(Int(stat.percentage))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            ProgressView(value: stat.percentage, total: 100)
                .tint(AppThemeConstants.accent)

            HStack(spacing: 12) {
                Label("\(stat.segmentCount) segments", systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Label(TranscriptSegment.formatTime(stat.totalDuration), systemImage: "clock")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
