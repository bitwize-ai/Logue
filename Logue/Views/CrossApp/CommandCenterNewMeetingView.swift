import SwiftUI

/// Meeting setup view for the Command Center — recording mode, template, and language pickers
/// before starting a recording.
struct CommandCenterNewMeetingView: View {
    @Binding var selectedRecordingMode: RecordingMode
    @Binding var selectedTemplate: MeetingTemplate
    @Binding var selectedLanguage: TranscriptionLanguage

    let onBack: () -> Void
    let onDismiss: () -> Void
    let onStartRecording: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ThinDivider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    recordingModeSection
                    templateSection
                    languageSection
                    startButton
                }
                .padding(16)
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

            Image(systemName: "record.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppThemeConstants.error)

            Text("New Meeting")
                .font(AppThemeConstants.islandTitle)
                .foregroundStyle(.primary)

            Spacer()
            DismissCircleButton(action: onDismiss, size: 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Recording Mode (Auto-Detect)

    @State private var detectedApp: ConferencingAppDetector.DetectedApp?

    private var recordingModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Source")
                .font(AppThemeConstants.islandLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: selectedRecordingMode == .onlineMeeting ? "display" : "mic.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    if let app = detectedApp, selectedRecordingMode == .onlineMeeting {
                        Text("\(app.name) detected — system audio enabled")
                            .font(AppThemeConstants.islandBody)
                    } else if selectedRecordingMode == .onlineMeeting {
                        Text("System audio enabled")
                            .font(AppThemeConstants.islandBody)
                    } else {
                        Text("Microphone recording")
                            .font(AppThemeConstants.islandBody)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if selectedRecordingMode == .onlineMeeting {
                            selectedRecordingMode = .inPerson
                        } else {
                            selectedRecordingMode = .onlineMeeting
                        }
                    }
                } label: {
                    Text(selectedRecordingMode == .onlineMeeting ? "Mic only" : "System audio")
                        .font(AppThemeConstants.islandCaption)
                        .foregroundStyle(AppThemeConstants.brandPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                    .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
            )
        }
        .onAppear {
            detectedApp = ConferencingAppDetector.detect()
            if detectedApp != nil {
                selectedRecordingMode = .onlineMeeting
            } else {
                selectedRecordingMode = .inPerson
            }
        }
    }

    // MARK: - Template

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Template")
                .font(AppThemeConstants.islandLabel)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(MeetingTemplate.allCases) { template in
                    templateChip(template)
                }
            }
        }
    }

    private func templateChip(_ template: MeetingTemplate) -> some View {
        let isSelected = selectedTemplate == template

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTemplate = template
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: template.iconName)
                    .font(.caption2.weight(.semibold))
                Text(template.label)
                    .font(AppThemeConstants.islandLabel)
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium, style: .continuous)
                    .fill(isSelected ? AppThemeConstants.brandPrimary : Color.primary.opacity(AppThemeConstants.opacitySubtle))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.label)
    }

    // MARK: - Language

    private var languageSection: some View {
        HStack {
            Text("Language")
                .font(AppThemeConstants.islandLabel)
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Button {
                        selectedLanguage = language
                    } label: {
                        HStack {
                            Text(language.label)
                            if selectedLanguage == language {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedLanguage.label)
                        .font(AppThemeConstants.islandBody)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                        .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button(action: onStartRecording) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .font(.subheadline.weight(.bold))
                Text("Start Recording")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(AppThemeConstants.error)
                    .shadow(color: AppThemeConstants.error.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start recording")
    }
}
