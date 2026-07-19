import SwiftUI

// MARK: - Quick Compose View

/// Minimal floating compose window for drafting and polishing text with AI.
struct QuickComposeView: View {
    let onDismiss: () -> Void

    @State private var draftText: String = ""
    @State private var polishEngine = PolishEngine()
    @State private var documentID: UUID?

    private let quickModes: [WritingMode] = [.improve, .moreFormal, .shorter, .expand, .rewrite]

    var body: some View {
        VStack(spacing: 0) {
            switch polishEngine.state {
            case .idle:
                composingView
            case .processing:
                PolishProcessingView(
                    modeName: polishEngine.selectedMode.displayName,
                    onCancel: { polishEngine.cancel() }
                )
            case .result:
                resultView
            case .error:
                PolishErrorView(
                    message: polishEngine.errorMessage ?? "Something went wrong.",
                    onBack: { polishEngine.reset() },
                    onRetry: { startPolish() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeConstants.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusPanel, style: .continuous)
                .stroke(AppThemeConstants.borderColor, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: polishEngine.state)
        .onDisappear {
            polishEngine.cancel()
            saveToNotes()
        }
    }

    // MARK: - Composing

    private var composingView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.top, -1)

                if draftText.isEmpty {
                    Text("Draft your thought, message, or tweet...")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                    .padding(.leading, 8)

                Text("\(draftText.count) chars")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                WritingModeChipBar(
                    modes: quickModes,
                    selectedMode: Bindable(polishEngine).selectedMode
                )

                PolishButton(isDisabled: draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    startPolish()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(AppThemeConstants.opacityLight)))
                .accessibilityLabel("Back")

                Spacer()

                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                Text("Result")
                    .font(.headline)

                Spacer()

                DismissCircleButton(action: onDismiss)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if let result = polishEngine.result {
                ScrollView(.vertical, showsIndicators: true) {
                    WritingDiffView(original: polishEngine.originalText, improved: result.improvedText)
                        .padding(16)
                }

                ThinDivider()

                RepolishChipBar(
                    modes: quickModes,
                    currentMode: polishEngine.selectedMode
                ) { mode in
                    polishEngine.reprocess(with: result.improvedText, mode: mode)
                    saveToNotes()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ThinDivider()

                PolishResultActionBar(
                    improved: result.improvedText,
                    showCopied: polishEngine.showCopied,
                    onDismiss: onDismiss,
                    onSave: nil,
                    onCopy: {
                        polishEngine.copyToClipboard(result.improvedText)
                        saveToNotes()
                    },
                    onInsert: nil
                )
            }
        }
    }

    // MARK: - Actions

    private func startPolish() {
        saveToNotes()
        polishEngine.polish(text: draftText)
    }

    private func goBack() {
        if let result = polishEngine.result {
            draftText = result.improvedText
        }
        polishEngine.reset()
    }

    // MARK: - Integration

    private func saveToNotes() {
        let textToSave = polishEngine.result?.improvedText ?? draftText
        let final = textToSave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else { return }

        if let id = documentID, let existing = DocumentStore.shared.documents.first(where: { $0.id == id }) {
            var updated = existing
            updated.body = final
            DocumentStore.shared.updateDocument(updated)
        } else {
            let components = final.components(separatedBy: .newlines)
            let firstLine = components.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Quick Note"
            let title = firstLine.count > 30 ? String(firstLine.prefix(30)) + "..." : firstLine

            let doc = DocumentStore.shared.createDocument(title: title)
            var updated = doc
            updated.body = final
            DocumentStore.shared.updateDocument(updated)
            documentID = doc.id
        }
    }
}
