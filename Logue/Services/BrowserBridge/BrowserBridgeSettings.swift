import Foundation

/// Whether the browser bridge may listen.
///
/// A separate type from the server so the setting can be read at launch — before anything has
/// started — and so the default is stated in exactly one place.
///
/// **On by default as of 1.1.0.** It shipped off, on the argument that every other opt-in in
/// Logue guards something the user can see and this one guards a socket they cannot. That
/// argument was right about the risk and wrong about the remedy: the extension is useless
/// until this is on, and a switch buried in Privacy meant the answer for almost everyone was
/// "off, and no idea why the extension does nothing".
///
/// What has *not* changed is the trade being real. The bridge listens on loopback only, so
/// nothing off the machine can reach it, but any program running as this user can. Two things
/// pay for the new default:
///
/// - `registerDefault()` supplies the value only when none is stored, so anyone who turned it
///   off deliberately stays off. An upgrade never re-enables it against their wishes.
/// - Nothing is switched on in silence: `BrowserExtensionPromo` tells the user it is listening,
///   in a callout that carries the off switch alongside the link to the extension.
enum BrowserBridgeSettings {
    /// Called once at launch, before anything reads the setting.
    ///
    /// `register(defaults:)` rather than a `?? true` at the read site: a fallback in the getter
    /// is invisible to `@AppStorage`, which reads `UserDefaults` directly, so the switch in
    /// Settings would have shown "off" while the server was running.
    static func registerDefault() {
        UserDefaults.standard.register(
            defaults: [AppConstants.UserDefaultsKeys.browserBridgeEnabled: true]
        )
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.browserBridgeEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.browserBridgeEnabled) }
    }
}
