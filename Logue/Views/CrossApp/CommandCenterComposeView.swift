import SwiftUI

/// Compose mode content for the Command Center — text editor, polish processing,
/// and result display with copy/save actions.
struct CommandCenterComposeView: View {
    let polishEngine: PolishEngine
    let draftText: Binding<String>
    let onBack: () -> Void
    let onDismiss: () -> Void
    let onStartCompose: () -> Void
    let onSaveToNotes: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ThinDivider()

            switch polishEngine.state {
            case .idle:
                editorView
            case .processing:
                PolishProcessingView(
                    modeName: polishEngine.selectedMode.displayName,
                    onCancel: { polishEngine.cancel() }
                )
            case .result:
                if let result = polishEngine.result {
                    resultView(result)
                }
            case .error:
                PolishErrorView(
                    message: polishEngine.errorMessage ?? "Something went wrong.",
                    onBack: { polishEngine.reset(); onBack() },
                    onRetry: { onStartCompose() }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(AppThemeConstants.opacityLight)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Image(systemName: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppThemeConstants.brandPrimary)

            Text(polishEngine.result != nil ? "Result" : "Quick Compose")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()
            DismissCircleButton(action: onDismiss, size: 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Editor

    private var editorView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: draftText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.top, -1)

                if draftText.wrappedValue.isEmpty {
                    Text("Draft your thought, message, or tweet\u{2026}")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxHeight: .infinity)

            ThinDivider()

            HStack(spacing: 10) {
                Text("\(draftText.wrappedValue.count) chars")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                WritingModeChipBar(
                    modes: WritingMode.quickActions,
                    selectedMode: Bindable(polishEngine).selectedMode
                )

                PolishButton(isDisabled: draftText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    onStartCompose()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Result

    private func resultView(_ result: WritingResult) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                WritingDiffView(original: draftText.wrappedValue, improved: result.improvedText)
                    .padding(16)
            }
            .frame(maxHeight: .infinity)

            ThinDivider()

            RepolishChipBar(
                modes: WritingMode.quickActions,
                currentMode: polishEngine.selectedMode
            ) { mode in
                polishEngine.reprocess(with: result.improvedText, mode: mode)
                onSaveToNotes()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            ThinDivider()

            PolishResultActionBar(
                improved: result.improvedText,
                showCopied: polishEngine.showCopied,
                onDismiss: onDismiss,
                onSave: nil,
                onCopy: {
                    polishEngine.copyToClipboard(result.improvedText)
                    onSaveToNotes()
                },
                onInsert: nil
            )
        }
    }
}
