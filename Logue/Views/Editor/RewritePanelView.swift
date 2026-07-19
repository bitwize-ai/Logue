import SwiftUI

// MARK: - RewriteStyle

enum RewriteStyle: String, CaseIterable, Identifiable {
    case professional = "Professional"
    case casual = "Casual"
    case academic = "Academic"
    case creative = "Creative"
    case technical = "Technical"
    case concise = "Concise"
    case persuasive = "Persuasive"
    case natural = "Natural"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .professional: "briefcase.fill"
        case .casual: "bubble.left.fill"
        case .academic: "graduationcap.fill"
        case .creative: "paintbrush.fill"
        case .technical: "terminal.fill"
        case .concise: "text.alignleft"
        case .persuasive: "megaphone.fill"
        case .natural: "person.fill.viewfinder"
        }
    }

    var description: String {
        switch self {
        case .professional: "Business-appropriate, polished tone"
        case .casual: "Friendly, conversational style"
        case .academic: "Scholarly, formal language"
        case .creative: "Expressive, engaging narrative"
        case .technical: "Documentation, code comments, and specs"
        case .concise: "Clear, brief, to the point"
        case .persuasive: "Compelling, convincing arguments"
        case .natural: "Natural, human-like tone — removes AI patterns, adds contractions and varied sentence structure"
        }
    }

    var color: Color {
        switch self {
        case .professional: AppThemeConstants.brandPrimary
        case .casual: AppThemeConstants.success
        case .academic: AppThemeConstants.categoryPurple
        case .creative: AppThemeConstants.warning
        case .technical: AppThemeConstants.accent
        case .concise: AppThemeConstants.brandPrimary
        case .persuasive: AppThemeConstants.error
        case .natural: AppThemeConstants.success
        }
    }

    // MARK: - Centralized Prompts

    /// System prompt for the rewrite LLM call.
    /// Sourced from `PromptRegistry.Writing.rewriteStyleInstruction`.
    var systemPrompt: String {
        PromptRegistry.Writing.rewriteStyleInstruction(for: rawValue)
    }
}

// MARK: - RewritePanelView

struct RewritePanelView: View {
    let document: WritingDocument
    var onApply: ((String) -> Void)?
    var onResultSave: ((RewriteResult?) -> Void)?

    @State private var selectedStyle: RewriteStyle = .professional
    @State private var originalText: String = ""
    @State private var rewrittenText: String = ""
    @State private var rewrittenStyle: RewriteStyle?
    @State private var cachedRewrittenText: String = ""
    @State private var isRewriting = false
    @State private var errorMessage: String?
    @State private var showApplyConfirmation = false
    @State private var didApply = false
    @State private var rewriteTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            content
        }
        .background(AppThemeConstants.surfaceBackground)
        .onAppear {
            if rewrittenText.isEmpty, let saved = document.rewriteResult {
                originalText = saved.originalText
                rewrittenText = saved.rewrittenText
                cachedRewrittenText = saved.rewrittenText
                if let style = RewriteStyle.allCases.first(where: { $0.rawValue.lowercased() == saved.style.lowercased() }) {
                    selectedStyle = style
                    rewrittenStyle = style
                }
            }
        }
        .onChange(of: selectedStyle) { _, newStyle in
            guard !cachedRewrittenText.isEmpty else { return }
            rewrittenText = newStyle == rewrittenStyle ? cachedRewrittenText : ""
            errorMessage = nil
        }
        .onDisappear { rewriteTask?.cancel() }
        .alert("Replace Document Text?", isPresented: $showApplyConfirmation) {
            Button("Replace", role: .destructive) {
                onApply?(rewrittenText)
                didApply = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your entire document with the rewritten version. You can undo this action.")
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Style selector + Rewrite button (compact row)
            HStack(spacing: 8) {
                Menu {
                    ForEach(RewriteStyle.allCases) { style in
                        Button {
                            selectedStyle = style
                        } label: {
                            Label(style.rawValue, systemImage: style.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedStyle.icon)
                        Text(selectedStyle.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: rewriteText) {
                    HStack(spacing: 4) {
                        if isRewriting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isRewriting ? "Rewriting..." : "Rewrite")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.small)
                .disabled(isRewriting || document.body.isEmpty || LLMEngineStatus.shared.isBusy)
                .accessibilityLabel("Rewrite text")
                .accessibilityHint("Rewrites your text in the selected style")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let errorMessage {
                errorState(errorMessage)
            } else if isRewriting, rewrittenText.isEmpty {
                loadingState
            } else if rewrittenText.isEmpty {
                emptyState
            } else {
                resultsView
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Rewriting your text…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a style and rewrite")
                .font(.subheadline.weight(.medium))
            Text("Transform your text with AI-powered rewriting")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(AppThemeConstants.error)
            Text("Rewrite Failed")
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button(action: rewriteText) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private var resultsView: some View {
        resultOnlyView
            .padding(AppThemeConstants.paddingLarge)
    }

    private var resultOnlyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: selectedStyle.icon)
                        .foregroundStyle(selectedStyle.color)
                    Text(selectedStyle.rawValue)
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Button(action: { copyToClipboard(rewrittenText) }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption)
                })
                .buttonStyle(.borderless)
            }

            Text(rewrittenText)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(AppThemeConstants.paddingMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppThemeConstants.textInputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                        .strokeBorder(selectedStyle.color.opacity(0.3), lineWidth: 1)
                )

            // Quick actions
            HStack(spacing: 8) {
                if didApply {
                    Button {
                        onApply?(originalText)
                        didApply = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Undo")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppThemeConstants.warning)
                    .accessibilityLabel("Undo rewrite")
                    .accessibilityHint("Restores the original document text")
                } else {
                    Button { showApplyConfirmation = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                            Text("Apply")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppThemeConstants.success)
                    .disabled(onApply == nil)
                    .accessibilityLabel("Apply rewrite")
                    .accessibilityHint("Replaces your document text with the rewritten version")
                }

                Button { rewriteText() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Try again")
                .accessibilityHint("Generates a new rewrite")
            }
        }
    }

    // MARK: - Actions

    private func rewriteText() {
        isRewriting = true
        originalText = document.body
        rewrittenText = ""
        cachedRewrittenText = ""
        rewrittenStyle = nil
        errorMessage = nil
        didApply = false

        rewriteTask = Task { @MainActor in
            let systemPrompt = selectedStyle.systemPrompt
            let userText = originalText

            do {
                let trimmed = try await withRetry {
                    let response = try await LLMEngine.shared.complete(
                        system: systemPrompt,
                        prompt: userText
                    )
                    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
                    return trimmed
                }
                rewrittenText = trimmed
                cachedRewrittenText = trimmed
                rewrittenStyle = selectedStyle
                onResultSave?(RewriteResult(
                    style: selectedStyle.rawValue,
                    originalText: originalText,
                    rewrittenText: trimmed
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
            isRewriting = false
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - StyleCard

private struct StyleCard: View {
    let style: RewriteStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: style.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : style.color)

                Text(style.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                    .fill(isSelected ? style.color : style.color.opacity(AppThemeConstants.activeOpacity))
            )
        }
        .buttonStyle(.plain)
        .help(style.description)
        .accessibilityLabel("\(style.rawValue) style")
        .accessibilityHint(style.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
