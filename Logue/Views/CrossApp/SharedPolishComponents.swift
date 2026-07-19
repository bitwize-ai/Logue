import SwiftUI

// MARK: - Thin Divider

/// Shared subtle divider used across floating panels and command center.
struct ThinDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppThemeConstants.separatorColor)
            .frame(height: 1)
    }
}

// MARK: - Dismiss Circle Button

/// Small circular X button for dismissing panels/sheets.
struct DismissCircleButton: View {
    let action: () -> Void
    var size: CGFloat = 28

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary.opacity(AppThemeConstants.opacityMuted))
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .background(Circle().fill(Color.primary.opacity(AppThemeConstants.opacityLight)))
        .accessibilityLabel("Close")
    }
}

// MARK: - Polish Processing View

/// Animated loading indicator shown while the LLM is polishing text.
struct PolishProcessingView: View {
    let modeName: String
    let onCancel: () -> Void

    @State private var animateDots = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { i in
                    Circle()
                        .fill(AppThemeConstants.brandPrimary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animateDots ? 1.2 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                            value: animateDots
                        )
                }
            }

            Text("Polishing with \(modeName)...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Button(action: onCancel) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(AppThemeConstants.opacityMedium)))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer()
        }
        .onAppear { animateDots = true }
    }
}

// MARK: - Polish Error View

/// Error state shown when polishing fails.
struct PolishErrorView: View {
    let message: String
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppThemeConstants.error)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button("Back", action: onBack)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                            .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle + 0.02))
                    )
                    .buttonStyle(.plain)

                Button("Try Again", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                            .fill(AppThemeConstants.brandPrimary.opacity(AppThemeConstants.borderOpacity))
                    )
                    .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

// MARK: - Polish Button

/// Primary "Polish + sparkles" action button.
struct PolishButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("Polish")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(isDisabled ? .white.opacity(0.4) : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppThemeConstants.brandPrimary.opacity(isDisabled ? 0.3 : 1))
                    .shadow(color: AppThemeConstants.brandPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityHint("Improve your text with AI")
    }
}

// MARK: - Writing Mode Chip

/// Selectable chip for a WritingMode, used in mode selector bars.
struct WritingModeChip: View {
    let mode: WritingMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.caption2.weight(.semibold))
                Text(mode.displayName)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                    .fill(isActive ? AppThemeConstants.brandPrimary.opacity(0.3) : Color.primary.opacity(AppThemeConstants.opacitySubtle))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                            .stroke(isActive ? AppThemeConstants.brandPrimary.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Writing Mode Chip Bar

/// Horizontal scrolling bar of WritingMode chips.
struct WritingModeChipBar: View {
    let modes: [WritingMode]
    @Binding var selectedMode: WritingMode
    var excludeSelected: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayedModes, id: \.self) { mode in
                    WritingModeChip(mode: mode, isActive: selectedMode == mode) {
                        selectedMode = mode
                    }
                }
            }
        }
    }

    private var displayedModes: [WritingMode] {
        excludeSelected ? modes.filter { $0 != selectedMode } : modes
    }
}

// MARK: - Re-polish Chip Bar

/// Horizontal bar of re-process chips (excludes current mode).
struct RepolishChipBar: View {
    let modes: [WritingMode]
    let currentMode: WritingMode
    let onSelect: (WritingMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modes.filter { $0 != currentMode }, id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        Text(mode.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.primary.opacity(AppThemeConstants.opacityLight)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Result Action Bar

/// Bottom action bar for polish results: Dismiss, Save, Copy, Insert.
struct PolishResultActionBar: View {
    let improved: String
    let showCopied: Bool
    let onDismiss: () -> Void
    let onSave: (() -> Void)?
    let onCopy: () -> Void
    let onInsert: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().stroke(Color.primary.opacity(AppThemeConstants.opacityMedium), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            if let onSave {
                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                        Text("Save to Doc")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.primary.opacity(AppThemeConstants.opacitySubtle + 0.02)))
                }
                .buttonStyle(.plain)
            }

            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc.fill")
                        .font(.caption.weight(.semibold))
                    Text(showCopied ? "Copied!" : "Copy")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(showCopied ? AppThemeConstants.success : .white)
                .padding(.horizontal, showCopied ? 12 : 16)
                .padding(.vertical, 9)
                .background(Capsule()
                    .fill(showCopied ? AppThemeConstants.success.opacity(AppThemeConstants.opacityMedium) : AppThemeConstants.brandPrimary))
            }
            .buttonStyle(.plain)

            if let onInsert {
                Button(action: onInsert) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.insert")
                            .font(.caption.weight(.bold))
                        Text("Insert")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(AppThemeConstants.brandPrimary)
                            .shadow(color: AppThemeConstants.brandPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
