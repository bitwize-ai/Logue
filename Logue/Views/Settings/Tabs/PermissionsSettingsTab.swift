import AVFoundation
import EventKit
import Speech
import SwiftUI

struct PermissionsSettingsTab: View {
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Environment(CalendarManager.self) private var calendarManager
    @State private var accessibilityPollTimer: Timer?

    /// Reads directly from the @Observable singleton so the UI always reflects the true state.
    private var accessibilityGranted: Bool {
        AccessibilityService.shared.isAccessibilityGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions")
                .font(.title3.bold())
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text("Logue needs these permissions to power its features. All processing stays on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            PrivacyBadge("No data ever leaves your device.")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Microphone
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Record and transcribe meetings on-device.",
                        isGranted: micGranted,
                        onRevoke: { openPrivacySettings(section: .microphone) },
                        onGrant: {
                            Task {
                                micGranted = await AVCaptureDevice.requestAccess(for: .audio)
                                if !micGranted {
                                    openPrivacySettings(section: .microphone)
                                }
                            }
                        }
                    )

                    Divider()

                    // Speech Recognition
                    PermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        description: "Voice-to-text for transcription and push-to-talk.",
                        isGranted: speechGranted,
                        onRevoke: { openPrivacySettings(section: .speechRecognition) },
                        onGrant: {
                            Task {
                                speechGranted = await requestSpeechPermission()
                                if !speechGranted {
                                    openPrivacySettings(section: .speechRecognition)
                                }
                            }
                        }
                    )

                    Divider()

                    // Calendar
                    PermissionRow(
                        icon: "calendar",
                        title: "Calendar",
                        description: "Show upcoming meetings and auto-populate titles.",
                        isGranted: calendarGranted,
                        onRevoke: { openPrivacySettings(section: .calendars) },
                        onGrant: {
                            Task {
                                await calendarManager.requestAccess()
                                calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                                if !calendarGranted {
                                    openPrivacySettings(section: .calendars)
                                }
                            }
                        }
                    )

                    // Calendar toggle + upcoming events (only when granted)
                    if calendarGranted {
                        Toggle(isOn: Binding(
                            get: { calendarManager.isEnabled },
                            set: { newValue in
                                if newValue {
                                    calendarManager.isEnabled = true
                                    UserDefaults.standard.set(true, forKey: "calendarIntegrationEnabled")
                                    calendarManager.refreshUpcomingEvents()
                                } else {
                                    calendarManager.disable()
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Upcoming Meetings")
                                    .font(.subheadline.weight(.medium))
                                Text("Display calendar events on the meetings home screen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppThemeConstants.accent)
                        .padding(.leading, 36)
                        .accessibilityLabel("Show Upcoming Meetings")
                        .accessibilityHint("Toggle display of calendar events on the meetings home screen")

                        PrivacyBadge("Calendar data is read locally via EventKit. Nothing is uploaded or shared.")
                            .padding(.leading, 36)

                        if calendarManager.isEnabled, !calendarManager.upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Upcoming Events")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(calendarManager.upcomingEvents.prefix(5)) { event in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.brandPrimary)
                                            .frame(width: 6, height: 6)
                                        Text(event.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(event.formattedTimeRange)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.leading, 36)
                        }
                    }

                    Divider()

                    // Accessibility
                    PermissionRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        description: "Writing assistant, auto-suggestions, and text replacement across apps.",
                        isGranted: accessibilityGranted,
                        onRevoke: { openPrivacySettings(section: .accessibility) },
                        onGrant: {
                            AccessibilityService.shared.checkAccessibilityPermission(prompt: true)
                            startAccessibilityPolling()
                        }
                    )
                }
                .padding(20)
            }
        }
        .task {
            refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAll()
        }
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
    }

    // MARK: - Helpers

    private func refreshAll() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        AccessibilityService.shared.checkAccessibilityPermission()
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        var pollCount = 0
        let maxPolls = 30 // Stop after 30 seconds
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                pollCount += 1
                let granted = AccessibilityService.shared.checkAccessibilityPermission()
                if granted || pollCount >= maxPolls {
                    accessibilityPollTimer?.invalidate()
                    accessibilityPollTimer = nil
                }
            }
        }
    }

    /// Known macOS Privacy preference pane sections.
    private enum PrivacySection: String {
        case microphone = "Microphone"
        case speechRecognition = "SpeechRecognition"
        case calendars = "Calendars"
        case accessibility = "Accessibility"
    }

    private func openPrivacySettings(section: PrivacySection) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRevoke: () -> Void
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "\(icon)")
                .font(.title3)
                .foregroundStyle(isGranted ? AppThemeConstants.success : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Button("Revoke") {
                    onRevoke()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Revoke \(title) permission")
                .accessibilityHint("Opens System Settings to manage \(title.lowercased()) permission")
            } else {
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.small)
                .accessibilityLabel("Grant \(title) permission")
                .accessibilityHint("Requests \(title.lowercased()) access for Logue")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) permission, \(isGranted ? "granted" : "not granted")")
    }
}
