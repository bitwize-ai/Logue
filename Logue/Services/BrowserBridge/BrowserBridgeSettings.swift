import Foundation

/// Whether the browser bridge may listen.
///
/// A separate type from the server so the setting can be read at launch — before anything has
/// started — and so the default is stated in exactly one place.
///
/// **Off by default, and deliberately so.** Every other opt-in in Logue guards something the user
/// can see; this one guards a socket they cannot. Turning it on means any program running as them
/// can reach the model, so it is their call to make rather than ours to make for them.
enum BrowserBridgeSettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.browserBridgeEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.browserBridgeEnabled) }
    }
}
