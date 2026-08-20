import Foundation

/// Whether to tell the user about the browser extension, and for how long.
///
/// Two jobs in one callout, which is why it is prominent rather than a line in Settings:
///
/// - The extension is new and invisible from inside the app. A What's New card is read once,
///   on the launch after an update, by someone who is usually trying to get to their work.
/// - As of 1.1.0 the loopback bridge is on by default (`BrowserBridgeSettings`). Turning on a
///   listening socket without saying so would be the wrong way to ship that, so the same
///   callout that advertises the extension is the one that discloses the socket and carries
///   the switch to close it.
///
/// It expires rather than waiting to be dismissed. A banner that stays until clicked is a
/// banner people learn to look past, and the disclosure has done its job once it has been on
/// screen for a week of actual use.
///
/// Pure, so the window is tested by moving `now` rather than by waiting seven days.
enum BrowserExtensionPromo {
    /// How long the callout stays after it is first shown.
    static let window: TimeInterval = 7 * 24 * 60 * 60

    /// - Parameters:
    ///   - firstShown: when it was first put on screen, or `nil` if it never has been.
    ///   - dismissed: whether the user closed it.
    ///   - now: the current time.
    static func shouldShow(firstShown: Date?, dismissed: Bool, now: Date) -> Bool {
        guard !dismissed else { return false }
        // Never shown yet: this launch is the first, and `firstShown` is stamped by the caller.
        guard let firstShown else { return true }
        // `>=` rather than `>`: a callout whose window closed exactly now is closed. Guarding
        // the future too, because a clock that moved backwards must not extend the window
        // indefinitely — the elapsed time is negative and would otherwise always be inside it.
        let elapsed = now.timeIntervalSince(firstShown)
        return elapsed >= 0 && elapsed < window
    }
}
