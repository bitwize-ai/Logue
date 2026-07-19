import AVFoundation
import ServiceManagement
import Speech
import SwiftUI

/// Multi-page onboarding wizard shown on first launch.
/// Guides users through permissions, model setup, and calendar integration.
struct OnboardingView: View {
    @Environment(ModelManager.self) var modelManager
    @State var currentPage = 0
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var calendarManager = CalendarManager.shared
    @State private var accessibilityPollTimer: Timer?

    /// Reads directly from the @Observable singleton so the UI always reflects the true state.
    private var accessibilityGranted: Bool {
        AccessibilityService.shared.isAccessibilityGranted
    }

    @State var didAutoAdvanceFromModel = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    let onComplete: () -> Void

    private let pageCount = 7

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: microphonePage
                case 2: modelPage
                case 3: calendarPage
                case 4: accessibilityPage
                case 5: launchAtLoginPage
                default: completePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation bar
            navigationBar
        }
        .frame(width: 720, height: 560)
        .background(AppThemeConstants.surfaceBackground)
        .task {
            // Check current permission states
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
            AccessibilityService.shared.checkAccessibilityPermission()
        }
        .onDisappear {
            // Clean up any active timers to prevent leaks if the view is dismissed
            stopAccessibilityPolling()
        }
    }

    // MARK: - Navigation Bar

    /// Whether navigation should be blocked (model page mid-download/activation).
    private var isNavigationBlocked: Bool {
        currentPage == 2 && modelManager.activeModelID == nil
    }

    private var navigationBar: some View {
        HStack {
            // Hide Back on the microphone page and during model download/activation.
            if currentPage > 0, currentPage < pageCount - 1, currentPage != 1, !isModelBusy {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentPage -= 1 }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Go back")
                .accessibilityHint("Returns to the previous onboarding step")
            }

            Spacer()

            // Page dots
            HStack(spacing: 6) {
                ForEach(0 ..< pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? AppThemeConstants.accent : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Step \(currentPage + 1) of \(pageCount)")

            Spacer()

            if currentPage < pageCount - 1 {
                Button(currentPage == 0 ? "Get Started" : "Next") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.regular)
                .disabled(isNavigationBlocked)
                .help(isNavigationBlocked && currentPage == 2
                    ? "Download and activate the AI model to continue"
                    : "")
                .accessibilityLabel(currentPage == 0 ? "Get Started" : "Next step")
                .accessibilityHint("Advances to the next onboarding step")
            } else {
                Button("Start Using Logue") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.regular)
                .accessibilityLabel("Start Using Logue")
                .accessibilityHint("Completes onboarding and opens the app")
            }
        }
        .padding(.horizontal, AppThemeConstants.paddingXLarge)
        .padding(.vertical, AppThemeConstants.paddingMedium)
        .background(AppThemeConstants.chromeBackground)
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.largeTitle)
                .foregroundStyle(AppThemeConstants.accent)

            VStack(spacing: 8) {
                Text("Welcome to Logue")
                    .font(.title.bold())
                Text("Your privacy-first AI meeting assistant")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "mic.fill", text: "Record and transcribe meetings on-device")
                featureRow(icon: "sparkles", text: "AI-powered summaries and action items")
                featureRow(icon: "doc.text", text: "Smart writing assistant for documents")
                featureRow(icon: "lock.shield.fill", text: "Everything stays on your Mac")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()

            PrivacyBadge("All processing happens locally. Your data never leaves your Mac.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Page 4: Microphone

    private var microphonePage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(micGranted ? AppThemeConstants.success.opacity(0.12) : AppThemeConstants.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: micGranted ? "checkmark.circle.fill" : "mic.circle.fill")
                    .font(.title)
                    .foregroundStyle(micGranted ? AppThemeConstants.success : AppThemeConstants.accent)
            }

            VStack(spacing: 8) {
                Text("Microphone Access")
                    .font(.title2.bold())
                Text("Logue needs your microphone to transcribe meetings and voice notes on-device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if micGranted, speechGranted {
                Label("Microphone & Speech Recognition Enabled", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppThemeConstants.success)
            } else {
                VStack(spacing: 10) {
                    if !micGranted {
                        Button("Grant Microphone Access") {
                            Task {
                                micGranted = await AVCaptureDevice.requestAccess(for: .audio)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppThemeConstants.accent)
                        .controlSize(.large)
                        .accessibilityLabel("Grant Microphone Access")
                        .accessibilityHint("Requests microphone permission for meeting recording")
                    }

                    if !speechGranted {
                        Button("Enable Speech Recognition") {
                            Task {
                                speechGranted = await requestSpeechPermission()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel("Enable Speech Recognition")
                        .accessibilityHint("Requests speech recognition permission for transcription")
                    }
                }
            }

            Spacer()

            PrivacyBadge("Audio is processed entirely on-device using Apple Speech.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Page 6: Calendar

    private var calendarPage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        calendarManager.isAuthorized
                            ? AppThemeConstants.success.opacity(0.12)
                            : AppThemeConstants.accent.opacity(0.12)
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: calendarManager.isAuthorized ? "checkmark.circle.fill" : "calendar.circle.fill")
                    .font(.title)
                    .foregroundStyle(calendarManager.isAuthorized ? AppThemeConstants.success : AppThemeConstants.accent)
            }

            VStack(spacing: 8) {
                Text("Calendar Integration")
                    .font(.title2.bold())
                Text("See upcoming meetings in Logue to quickly start recording when a meeting begins.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if calendarManager.isAuthorized {
                Label("Calendar Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppThemeConstants.success)
            } else {
                VStack(spacing: 10) {
                    Button("Connect Calendar") {
                        Task { await calendarManager.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.large)
                    .accessibilityLabel("Connect Calendar")
                    .accessibilityHint("Requests calendar access to show upcoming meetings")

                    Button("Skip — I'll set this up later") {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Skip calendar setup")
                }
            }

            Spacer()

            PrivacyBadge("Calendar data is read locally. Nothing is uploaded.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Page 7: Accessibility

    private var accessibilityPage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        accessibilityGranted
                            ? AppThemeConstants.success.opacity(0.12)
                            : AppThemeConstants.accent.opacity(0.12)
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "accessibility.fill")
                    .font(.title)
                    .foregroundStyle(accessibilityGranted ? AppThemeConstants.success : AppThemeConstants.accent)
            }

            VStack(spacing: 8) {
                Text("Accessibility Access")
                    .font(.title2.bold())
                Text("Logue uses Accessibility to power the writing assistant, auto-suggestions, and text replacement across all apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if accessibilityGranted {
                Label("Accessibility Access Enabled", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppThemeConstants.success)
            } else {
                VStack(spacing: 10) {
                    Button("Grant Accessibility Access") {
                        AccessibilityService.shared.checkAccessibilityPermission(prompt: true)
                        startAccessibilityPolling()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.large)
                    .accessibilityLabel("Grant Accessibility Access")
                    .accessibilityHint("Opens system settings to grant accessibility permission")

                    Button("Skip — I'll set this up later") {
                        stopAccessibilityPolling()
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Skip accessibility setup")
                }
            }

            Spacer()

            PrivacyBadge("Accessibility is used only for text interactions. No data leaves your Mac.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let granted = AccessibilityService.shared.checkAccessibilityPermission()
                if granted {
                    stopAccessibilityPolling()
                }
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    // MARK: - Page 8: Launch at Login

    private var launchAtLoginPage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppThemeConstants.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "power.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppThemeConstants.accent)
            }

            VStack(spacing: 8) {
                Text("Launch at Login")
                    .font(.title2.bold())
                Text(
                    "Logue lives in your menu bar and is always ready when you need it."
                        + " Enable launch at login so it's available whenever you start your Mac."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }

            Toggle("Launch Logue at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }
                .frame(maxWidth: 240)

            Button("Skip — I'll set this up later") {
                withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Skip launch at login setup")

            Spacer()

            PrivacyBadge("Logue runs locally in your menu bar. No background data collection.")
                .padding(.bottom, 8)
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Page 9: Complete

    private var completePage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppThemeConstants.success.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppThemeConstants.success)
            }

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.title2.bold())
                Text("Here are some shortcuts to get you started:")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                shortcutRow(keys: "Cmd + N", label: "New Document")
                shortcutRow(keys: "Cmd + Shift + N", label: "New Meeting")
                shortcutRow(keys: ShortcutManager.shared.commandCenterShortcut.displayString, label: "Ask Logue (global)")
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .fill(AppThemeConstants.chromeBackground)
            )

            Spacer()
        }
        .padding(AppThemeConstants.paddingXLarge)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppThemeConstants.accent)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }

    private func shortcutRow(keys: String, label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                        .fill(AppThemeConstants.surfaceBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                                .strokeBorder(Color.primary.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
                        )
                )
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
