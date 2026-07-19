import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.bitwize.logue", category: "VocabularyEnhancement")

// MARK: - VocabSuggestion

struct VocabSuggestion: Identifiable, Codable {
    let id: UUID
    let original: String
    let suggestion: String
    let explanation: String
    let category: String

    init(id: UUID = UUID(), original: String, suggestion: String, explanation: String, category: String) {
        self.id = id
        self.original = original
        self.suggestion = suggestion
        self.explanation = explanation
        self.category = category
    }
}

// MARK: - VocabularyEnhancementPanelView

struct VocabularyEnhancementPanelView: View {
    let document: WritingDocument
    /// Called when user taps Replace — returns true if replacement succeeded.
    var onReplace: ((String, String) -> Bool)?
    /// Called when user taps a suggestion card to scroll to the text in the editor.
    var onScrollToText: ((String) -> Void)?
    var onSuggestionsSave: (([VocabSuggestion]?) -> Void)?

    @State private var isEnhancing = false
    @State private var suggestions: [VocabSuggestion] = []
    @State private var errorMessage: String?
    @State private var appliedIDs: Set<UUID> = []
    @State private var enhanceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AppThemeConstants.surfaceBackground)
        .onAppear {
            if suggestions.isEmpty, let saved = document.vocabSuggestions {
                suggestions = saved
            }
        }
        .onDisappear { enhanceTask?.cancel() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                if isEnhancing {
                    Button {
                        enhanceTask?.cancel()
                        isEnhancing = false
                    } label: {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Cancel")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: enhanceVocabulary) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Enhance")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)
                    .disabled(document.body.isEmpty || LLMEngineStatus.shared.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityLabel("Enhance vocabulary")
            .accessibilityHint("Suggests stronger synonyms and better phrasing for your text")

            Divider()

            if let errorMessage {
                errorView(errorMessage)
            } else if isEnhancing, suggestions.isEmpty {
                loadingState
            } else if suggestions.isEmpty {
                emptyState
            } else {
                resultsView
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat.alt")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Enhance your vocabulary")
                .font(.subheadline.weight(.medium))
            Text("Find stronger synonyms and better phrasing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Analyzing vocabulary…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(AppThemeConstants.error)
            Text("Analysis Failed")
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button(action: enhanceVocabulary) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                Text("\(suggestions.count) suggestions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let pending = suggestions.filter { !appliedIDs.contains($0.id) }
                if !pending.isEmpty, onReplace != nil {
                    Button {
                        var appliedCount = 0
                        for item in pending where onReplace?(item.original, item.suggestion) == true {
                            appliedIDs.insert(item.id)
                            appliedCount += 1
                        }
                        if appliedCount < pending.count {
                            errorMessage = "Applied \(appliedCount) of \(pending.count) suggestions. Some text may have changed."
                        }
                    } label: {
                        Text("Apply All")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(suggestions) { item in
                        VocabSuggestionCard(
                            suggestion: item,
                            isApplied: appliedIDs.contains(item.id),
                            onReplace: onReplace != nil ? {
                                if onReplace?(item.original, item.suggestion) == true {
                                    appliedIDs.insert(item.id)
                                }
                            } : nil,
                            onSelect: { onScrollToText?(item.original) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private func enhanceVocabulary() {
        isEnhancing = true
        suggestions = []
        errorMessage = nil
        appliedIDs = []

        enhanceTask = Task { @MainActor in
            let systemPrompt = PromptRegistry.Verification.vocabularySystem.content

            do {
                let maxChars = LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens)
                let safeBody = String(document.body.prefix(maxChars))
                let parsed = try await withRetry {
                    let response = try await LLMEngine.shared.complete(
                        system: systemPrompt,
                        prompt: "<content>\n\(safeBody)\n</content>",
                        maxTokens: 2048
                    )
                    let parsed = parseVocabSuggestions(response)
                    guard !parsed.isEmpty else { throw LLMError.emptyResponse }
                    return parsed
                }
                guard !Task.isCancelled else { return }
                // Discard suggestions whose original text doesn't exist in the document
                let validated = parsed.filter { item in
                    safeBody.range(of: item.original, options: .caseInsensitive) != nil
                }
                if validated.count < parsed.count {
                    logger.warning(
                        "Discarded \(parsed.count - validated.count) hallucinated suggestions (not found in document)"
                    )
                }
                suggestions = validated
                onSuggestionsSave?(validated)
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isEnhancing = false
        }
    }

    private func parseVocabSuggestions(_ text: String) -> [VocabSuggestion] {
        guard let arrayStart = text.firstIndex(of: "["),
              let arrayEnd = text.lastIndex(of: "]"),
              arrayStart < arrayEnd
        else {
            logger.warning("parseVocabSuggestions: no JSON array found in output (\(text.count) chars)")
            return []
        }

        let jsonString = String(text[arrayStart ... arrayEnd])
        guard let data = jsonString.data(using: .utf8) else {
            logger.warning("parseVocabSuggestions: failed to encode JSON string to UTF-8")
            return []
        }

        let items: [[String: Any]]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                logger.warning("parseVocabSuggestions: JSON root is not an array of objects")
                logger.debug("Raw output prefix: \(String(text.prefix(500)), privacy: .private)")
                return []
            }
            items = parsed
        } catch {
            logger.warning("parseVocabSuggestions decode failed: \(String(describing: error), privacy: .public)")
            logger.debug("Raw output prefix: \(String(text.prefix(500)), privacy: .private)")
            return []
        }

        return items.compactMap { item in
            guard let original = item["original"] as? String,
                  let suggestion = item["suggestion"] as? String
            else { return nil }

            return VocabSuggestion(
                original: original,
                suggestion: suggestion,
                explanation: item["explanation"] as? String ?? "",
                category: item["category"] as? String ?? "weak"
            )
        }
    }
}

// MARK: - VocabSuggestionCard

private struct VocabSuggestionCard: View {
    let suggestion: VocabSuggestion
    let isApplied: Bool
    var onReplace: (() -> Void)?
    var onSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(suggestion.category.capitalized)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(AppThemeConstants.activeOpacity), in: Capsule())

                Spacer()

                if isApplied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                        Text("Applied")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppThemeConstants.success)
                } else if let onReplace {
                    Button(action: onReplace) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Replace")
                        }
                        .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                }
            }

            HStack(spacing: 6) {
                Text(suggestion.original)
                    .font(.subheadline)
                    .strikethrough(isApplied, color: .secondary)
                    .foregroundStyle(isApplied ? .secondary : .primary)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(suggestion.suggestion)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isApplied ? AppThemeConstants.success : AppThemeConstants.brandPrimary)
            }

            if !suggestion.explanation.isEmpty {
                Text(suggestion.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(isApplied ? AppThemeConstants.success.opacity(AppThemeConstants.opacitySubtle) : Color.primary
                    .opacity(AppThemeConstants.opacitySubtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .strokeBorder(
                    isApplied ? AppThemeConstants.success.opacity(AppThemeConstants.opacityMedium) : Color.primary
                        .opacity(AppThemeConstants.opacityLight),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }

    private var categoryColor: Color {
        switch suggestion.category.lowercased() {
        case "overused": AppThemeConstants.warning
        case "weak": AppThemeConstants.error
        case "informal": AppThemeConstants.categoryPurple
        case "imprecise": AppThemeConstants.brandPrimary
        case "repetitive": AppThemeConstants.warning
        default: .secondary
        }
    }
}
