import SwiftUI

// MARK: - Generation Tracker

/// Tracks in-flight AI generation tasks so they survive popover close/reopen.
/// Lives in the environment, shared across all popovers for a given space.
@MainActor @Observable
final class SpaceAIGenerationTracker {
    /// Keys currently being generated (e.g. "summary", "actionItems").
    var generatingKeys: Set<String> = []
    /// Error messages keyed by insight key.
    var errors: [String: String] = [:]

    func isGenerating(_ key: String) -> Bool {
        generatingKeys.contains(key)
    }

    func run(
        key: String,
        spaceID: UUID,
        action: @escaping (UUID) async throws -> String
    ) {
        guard !generatingKeys.contains(key) else { return }
        generatingKeys.insert(key)
        errors.removeValue(forKey: key)
        Task {
            defer { generatingKeys.remove(key) }
            do {
                _ = try await action(spaceID)
            } catch {
                errors[key] = "Failed to generate: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Popover View

/// Generic popover for all space AI actions (summary, action items, decisions, status update).
/// Reads from persisted `Space.aiInsights` and uses content signature staleness detection.
/// Generation state is tracked via `SpaceAIGenerationTracker` so tasks survive popover dismiss.
struct SpaceAIPopover: View {
    let title: String
    let icon: String
    let insightKey: String
    let spaceID: UUID
    let action: (UUID) async throws -> String
    let onDismiss: () -> Void

    @Environment(SpaceStore.self) private var spaceStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceAIGenerationTracker.self) private var tracker

    private var space: Space? {
        spaceStore.space(for: spaceID)
    }

    private var insight: SpaceAIInsight? {
        space?.aiInsights?[insightKey]
    }

    private var currentSignature: String {
        SpaceStore.contentSignature(
            spaceID: spaceID,
            spaceStore: spaceStore,
            documentStore: documentStore,
            meetingStore: meetingStore
        )
    }

    private var isStale: Bool {
        guard let insight else { return false }
        return insight.contentSignature != currentSignature
    }

    private var isGenerating: Bool {
        tracker.isGenerating(insightKey)
    }

    private var errorMessage: String? {
        tracker.errors[insightKey]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if insight != nil, !isGenerating {
                Divider()
                footer
            }
        }
        .frame(width: 420)
        .frame(maxHeight: 520)
        .onAppear {
            if isStale, !isGenerating {
                tracker.run(key: insightKey, spaceID: spaceID, action: action)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                Text(title)
                    .font(.headline)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isGenerating, insight == nil {
            generatingState
        } else if let insight {
            insightContent(insight)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No \(title.lowercased()) generated yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                tracker.run(key: insightKey, spaceID: spaceID, action: action)
            } label: {
                Label("Generate", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.accent)
            .controlSize(.regular)
            .disabled(isGenerating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var generatingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Generating \(title.lowercased())…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func insightContent(_ insight: SpaceAIInsight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(LocalizedStringKey(insight.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            HStack(spacing: 8) {
                Text("Generated \(insight.generatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if isGenerating {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Updating…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if isStale {
                    Text("· Content has changed")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                tracker.run(key: insightKey, spaceID: spaceID, action: action)
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isGenerating)

            Spacer()

            Button {
                if let content = insight?.content {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                if let content = insight?.content {
                    var doc = documentStore.createDocument(inSpace: spaceID)
                    doc.title = title
                    doc.body = content
                    documentStore.updateDocument(doc)
                    documentStore.selectedDocumentID = doc.id
                    onDismiss()
                }
            } label: {
                Label("Save as Document", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.accent)
            .controlSize(.small)
        }
        .padding()
    }
}
