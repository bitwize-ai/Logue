import Foundation

/// Shared state that tells SettingsView which tab to show when it opens.
@Observable
@MainActor
final class SettingsNavigator {
    static let shared = SettingsNavigator()
    private init() {}

    var pendingTab: SettingsTab?
    var pendingCheckForUpdates: Bool = false
}

/// Type-safe settings tab identifiers.
enum SettingsTab: Int {
    case general = 0
    case models = 1
    case ai = 2
    case shortcuts = 7
    case privacy = 8
    case permissions = 4
    case backup = 5
    case about = 6
}
