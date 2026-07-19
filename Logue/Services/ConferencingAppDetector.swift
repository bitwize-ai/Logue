import AppKit

/// Detects running conferencing/meeting apps to auto-suggest system audio capture.
enum ConferencingAppDetector {
    struct DetectedApp: Sendable {
        let name: String
        let bundleID: String
    }

    private static let knownApps: [(name: String, bundleID: String)] = [
        ("Zoom", "us.zoom.xos"),
        ("Microsoft Teams", "com.microsoft.teams"),
        ("Microsoft Teams", "com.microsoft.teams2"),
        ("Slack", "com.tinyspeck.slackmacgap"),
        ("Discord", "com.hnc.Discord"),
        ("FaceTime", "com.apple.FaceTime"),
        ("Skype", "com.skype.skype"),
        ("WebEx", "com.cisco.webexmeetings"),
        // Google Meet omitted — Chrome's bundle ID matches all browsing, not just Meet
    ]

    /// Returns the first detected running conferencing app, or nil if none found.
    @MainActor
    static func detect() -> DetectedApp? {
        for app in knownApps
            where !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
        {
            return DetectedApp(name: app.name, bundleID: app.bundleID)
        }
        return nil
    }
}
