import SwiftUI

/// Floating popover that drives the inline-rewrite flow:
/// `awaitingInstruction` → `rewriting` → `preview` (Accept / Reject / Regenerate) → `idle`.
///
/// Anchored at `state.anchorPosition` inside the BlockEditor overlay. Dismisses on Escape.
struct InlineRewritePopover: View {
    @Bindable var state: InlineRewriteState
    @FocusState private var isInstructionFocused: Bool

    private static let popoverWidth: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if shouldShowActionRow {
                Divider()
                actionRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: Self.popoverWidth)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(AppThemeConstants.panelShadowOpacity),
            radius: AppThemeConstants.panelShadowRadius,
            x: 0,
            y: AppThemeConstants.panelShadowY
        )
        .onKeyPress(.escape) {
            state.reject()
            return .handled
        }
        .onAppear {
            isInstructionFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.accent)

            Text("Rewrite selection")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                state.reject()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close rewrite")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content (phase-dependent)

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .awaitingInstruction, .rewriting:
            instructionField
                .disabled(state.isRewriting || LLMEngineStatus.shared.isBusy)

            if state.isRewriting {
                HStack(spacing: 8) {
                    PulsingDot(size: 6)
                    Text("Generating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } else {
                originalPreview
                    .padding(.top, 10)
            }

        case .preview:
            diffPreview

        case let .error(message):
            errorRow(message)

        case .idle:
            EmptyView()
        }
    }

    private var instructionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                "Tell the AI what to change…",
                text: $state.instruction,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1 ... 4)
            .padding(10)
            .background(
                AppThemeConstants.surfaceBackground,
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
            .focused($isInstructionFocused)
            .onSubmit {
                if state.canSubmit {
                    state.submitInstruction()
                }
            }
            .accessibilityLabel("Rewrite instruction")

            Text("E.g. \"make this shorter\" · \"more formal\" · \"turn into a bulleted list\"")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var originalPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selected text")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            Text(state.originalText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    AppThemeConstants.surfaceBackground,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                )
                .textSelection(.enabled)
        }
    }

    private var diffPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                label("Original", color: AppThemeConstants.error)
                Text(state.originalText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strikethrough()
                    .padding(8)
                    .background(
                        AppThemeConstants.error.opacity(AppThemeConstants.opacityLight),
                        in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                    )
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                label("Rewrite", color: AppThemeConstants.success)
                Text(state.rewrittenText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        AppThemeConstants.success.opacity(AppThemeConstants.opacityLight),
                        in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .tracking(0.5)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(
            AppThemeConstants.error.opacity(AppThemeConstants.opacityLight),
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
        )
    }

    // MARK: - Action Row

    private var shouldShowActionRow: Bool {
        switch state.phase {
        case .awaitingInstruction, .preview, .error: true
        case .idle, .rewriting: false
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch state.phase {
        case .awaitingInstruction:
            HStack {
                Spacer()
                Button("Cancel") { state.reject() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    state.submitInstruction()
                } label: {
                    Label("Rewrite", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppThemeConstants.accent)
                .disabled(!state.canSubmit || LLMEngineStatus.shared.isBusy)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘↩)")
            }

        case .preview:
            HStack(spacing: 8) {
                Button {
                    state.regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(LLMEngineStatus.shared.isBusy)

                Spacer()

                Button("Reject") { state.reject() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    if state.accept() {
                        HapticFeedback.levelChange()
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppThemeConstants.success)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Accept (⌘↩)")
            }

        case .error:
            HStack {
                Spacer()
                Button("Close") { state.reject() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    // Reset to awaitingInstruction so the user can try again
                    state.regenerate()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppThemeConstants.accent)
            }

        case .idle, .rewriting:
            EmptyView()
        }
    }
}
