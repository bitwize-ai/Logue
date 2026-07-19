import SwiftUI

/// A row that displays a keyboard shortcut binding with a "Change" button.
/// Entering recording mode captures the next key combo from the user.
struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: CustomShortcut
    let onUpdate: (CustomShortcut) -> Void

    @State private var isRecording = false
    @State private var recordingMonitor: Any?

    var body: some View {
        HStack {
            Text(title)
                .font(.body)

            Spacer()

            if isRecording {
                Text("Press shortcut…")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(AppThemeConstants.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                            .fill(AppThemeConstants.accent.opacity(AppThemeConstants.activeOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                                    .strokeBorder(AppThemeConstants.accent.opacity(AppThemeConstants.opacityStrong), lineWidth: 1)
                            )
                    )

                Button("Cancel") {
                    stopRecording()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cancel shortcut recording")
            } else {
                Text(shortcut.displayString)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                            .fill(AppThemeConstants.surfaceBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                                    .strokeBorder(AppThemeConstants.borderColor, lineWidth: 1)
                            )
                    )

                Button("Change") {
                    startRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Change \(title) shortcut")
                .accessibilityHint("Records a new keyboard shortcut for \(title)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) shortcut, \(shortcut.displayString)")
    }

    // MARK: - Recording

    private func startRecording() {
        ShortcutManager.shared.stopListening()
        isRecording = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Bare Escape cancels
            if event.keyCode == 53,
               event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
            {
                stopRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier key
            guard !mods.isEmpty else { return nil }

            let newShortcut = CustomShortcut(keyCode: event.keyCode, modifierFlags: mods.rawValue)
            shortcut = newShortcut
            onUpdate(newShortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        isRecording = false
        ShortcutManager.shared.startListening()
    }
}
