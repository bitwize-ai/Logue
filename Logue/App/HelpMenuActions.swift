import AppKit
import Darwin

/// Centralised actions for every item in the Help menu bar menu.
@MainActor
enum HelpMenuActions {
    // MARK: - URLs

    private enum URLs {
        // Compile-time constant strings — URL(string:) will never return nil.
        static let documentation = URL(string: "https://bitwize.ai/docs")!
        static let linkedin = URL(string: "https://www.linkedin.com/company/bitwize-ai/")!
        static let aboutUs = URL(string: "https://bitwize.ai/")!
        static let privacyPolicy = URL(string: "https://bitwize.ai/privacy")!
        static let termsOfService = URL(string: "https://bitwize.ai/terms")!
        static let chromeExtension = URL(
            string: "https://chromewebstore.google.com/detail/logue/gaegipceeccdchdffamdphfiegfeenhc"
        )!
    }

    static func openDocumentation() {
        NSWorkspace.shared.open(URLs.documentation)
    }

    /// The extension lives in the Chrome Web Store, not in this build, so the only thing the
    /// app can do about it is point. Kept in Help beside Documentation rather than buried in
    /// Settings: it is the menu people open when looking for the parts of Logue they have
    /// not found yet, and the What's New card announcing it is seen once.
    static func openChromeExtension() {
        NSWorkspace.shared.open(URLs.chromeExtension)
    }

    static func openKeyboardShortcuts() {
        NotificationCenter.default.post(name: .openKeyboardShortcutsWindow, object: nil)
    }

    static func checkForUpdates() {
        NotificationCenter.default.post(name: .openSettingsAboutAndCheckUpdates, object: nil)
    }

    static func showWhatsNew() {
        NotificationCenter.default.post(name: .showWhatsNew, object: nil)
    }

    static func openResourceUsage() {
        NotificationCenter.default.post(name: .openResourceUsageWindow, object: nil)
    }

    static func openPrivacyPolicy() {
        NSWorkspace.shared.open(URLs.privacyPolicy)
    }

    static func openTermsOfService() {
        NSWorkspace.shared.open(URLs.termsOfService)
    }

    static func joinLinkedIn() {
        NSWorkspace.shared.open(URLs.linkedin)
    }

    static func openAboutUs() {
        NSWorkspace.shared.open(URLs.aboutUs)
    }

    static func reportBug() {
        NotificationCenter.default.post(name: .openReportBugWindow, object: nil)
    }

    static func contactSupport() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = Self.hwModel()

        let subject = "[Logue Support] v\(appVersion)"
        let body = """
        Hi,

        Describe what happened:


        ---
        App: \(appVersion) (\(buildNumber)) · macOS \(macOSVersion)
        Device: \(deviceModel)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@bitwize.ai"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]

        guard let mailtoURL = components.url else { return }
        NSWorkspace.shared.open(mailtoURL)
    }

    // MARK: - Private helpers

    private static func hwModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
