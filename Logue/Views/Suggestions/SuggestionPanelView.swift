import SwiftUI

/// Proofreader tool panel: clean flat list of suggestion cards.
struct SuggestionPanelView: View {
    let suggestions: [Suggestion]
    let isAnalyzing: Bool
    let onAccept: (Suggestion) -> Void
    let onDismiss: (Suggestion) -> Void
    var onAcceptAll: (() -> Void)?
    var onSuggestionSelected: ((Suggestion) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            suggestionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Suggestion List

    @ViewBuilder
    private var suggestionList: some View {
        if suggestions.isEmpty {
            VStack(spacing: 10) {
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analysing your writing…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No issues found")
                        .font(.subheadline.weight(.medium))
                    Text("Spelling issues appear as you type.\nUse Review to run a full analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if suggestions.count >= 2, let onAcceptAll {
                        HStack {
                            Text("\(suggestions.count) suggestions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                onAcceptAll()
                            } label: {
                                Label("Fix All", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(AppThemeConstants.accent)
                        }
                    }
                    ForEach(suggestions) { suggestion in
                        SuggestionCardView(
                            suggestion: suggestion,
                            onAccept: { onAccept(suggestion) },
                            onDismiss: { onDismiss(suggestion) },
                            onSelect: { onSuggestionSelected?(suggestion) }
                        )
                    }
                    if isAnalyzing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Finding more suggestions…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(12)
            }
        }
    }
}
