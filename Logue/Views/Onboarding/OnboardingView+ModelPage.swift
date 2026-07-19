import SwiftUI

// MARK: - Model Page

extension OnboardingView {
    var isModelBusy: Bool {
        modelManager.downloadingID != nil || modelManager.isActivating
    }

    var hasModelError: Bool {
        modelManager.downloadError != nil || modelManager.activationError != nil
    }

    var modelPage: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(modelPageIconBackground)
                    .frame(width: 72, height: 72)
                if modelManager.isActivating {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: modelPageIcon)
                        .font(.title)
                        .foregroundStyle(modelPageIconColor)
                }
            }

            // Title & subtitle
            VStack(spacing: 8) {
                Text(modelPageTitle)
                    .font(.title2.bold())
                Text(modelPageSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // Action area
            if modelManager.activeModelID != nil {
                // Complete — auto-advance only once (not when navigating back)
                Label("AI Model Ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppThemeConstants.success)
                    .task {
                        guard !didAutoAdvanceFromModel else { return }
                        didAutoAdvanceFromModel = true
                        try? await Task.sleep(for: AppConstants.Delays.onboardingAutoAdvance)
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    }
            } else if modelManager.downloadingID != nil {
                // Downloading — progress bar
                VStack(spacing: 8) {
                    ProgressView(value: modelManager.downloadProgress)
                        .frame(maxWidth: 300)
                    HStack {
                        Text("\(Int(modelManager.downloadProgress * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let size = ModelConfiguration.onboardingModel.sizeGB {
                            Text("~\(String(format: "%.1f", size)) GB")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: 300)
                }
            } else if modelManager.isActivating {
                // Activating — handled by spinner icon above
                EmptyView()
            } else if hasModelError {
                // Error — retry button
                VStack(spacing: 12) {
                    Text(modelManager.downloadError ?? modelManager.activationError ?? "Unknown error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button("Try Again") {
                        modelManager.downloadAndActivate(ModelConfiguration.onboardingModel, autoActivate: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.large)
                    .disabled(isModelBusy)
                    .accessibilityLabel("Try downloading again")
                    .accessibilityHint("Retries the AI model download")
                }
            } else {
                // Ready to download
                VStack(spacing: 12) {
                    if let size = ModelConfiguration.onboardingModel.sizeGB {
                        Text("~\(String(format: "%.1f", size)) GB download")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }

                    Button("Download") {
                        modelManager.downloadAndActivate(ModelConfiguration.onboardingModel, autoActivate: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.large)
                    .disabled(isModelBusy)
                    .accessibilityLabel("Download AI model")
                    .accessibilityHint("Downloads the AI model required for writing suggestions and meeting summaries")
                }
            }

            Spacer()

            PrivacyBadge("Models run locally via Apple Silicon ML acceleration.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Model Page Helpers

    var modelPageIcon: String {
        if modelManager.activeModelID != nil {
            "checkmark.circle.fill"
        } else if hasModelError {
            "exclamationmark.triangle.fill"
        } else if modelManager.downloadingID != nil {
            "arrow.down.circle.fill"
        } else {
            "arrow.down.circle.fill"
        }
    }

    var modelPageIconColor: Color {
        if modelManager.activeModelID != nil {
            AppThemeConstants.success
        } else if hasModelError {
            .orange
        } else {
            AppThemeConstants.accent
        }
    }

    var modelPageIconBackground: Color {
        if modelManager.activeModelID != nil {
            AppThemeConstants.success.opacity(0.12)
        } else if hasModelError {
            AppThemeConstants.warning.opacity(AppThemeConstants.activeOpacity)
        } else {
            AppThemeConstants.accent.opacity(0.12)
        }
    }

    var modelPageTitle: String {
        if modelManager.activeModelID != nil {
            "AI Model Ready"
        } else if modelManager.isActivating {
            "Setting Up AI Model…"
        } else if modelManager.downloadingID != nil {
            "Downloading AI Model…"
        } else if hasModelError {
            "Download Failed"
        } else {
            "Download AI Model"
        }
    }

    var modelPageSubtitle: String {
        if modelManager.activeModelID != nil {
            "Everything is set up for AI-powered features."
        } else if modelManager.isActivating {
            "Preparing the model for first use."
        } else if modelManager.downloadingID != nil {
            "This may take a few minutes depending on your connection."
        } else if hasModelError {
            "Something went wrong. Please check your connection and try again."
        } else {
            "Logue needs a small AI model to power writing suggestions, " +
                "meeting summaries, and chat. This is a one-time download."
        }
    }
}
