import Foundation
import Testing

@testable import Logue

/// When the browser-extension callout is on screen.
///
/// It is not only an advert: 1.1.0 turns the loopback bridge on by default, and this callout is
/// where that is disclosed. So "does it appear, and for how long" is a question about whether
/// the user was told, which is why the window is pinned rather than left to a constant nobody
/// reads.
@Suite("BrowserExtensionPromo")
struct BrowserExtensionPromoTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("A user who has never seen it is shown it")
    func neverShownIsShown() {
        #expect(BrowserExtensionPromo.shouldShow(firstShown: nil, dismissed: false, now: now))
    }

    @Test("Dismissing it ends it, even on the first day")
    func dismissalWins() {
        #expect(
            BrowserExtensionPromo.shouldShow(
                firstShown: now.addingTimeInterval(-60), dismissed: true, now: now
            ) == false
        )
        // Dismissal beats "never shown" too, so a stale flag cannot resurrect it.
        #expect(BrowserExtensionPromo.shouldShow(firstShown: nil, dismissed: true, now: now) == false)
    }

    @Test("It stays for the week")
    func staysInsideTheWindow() {
        for elapsed in [0, 60, 60 * 60 * 24, 60 * 60 * 24 * 6] {
            let shown = now.addingTimeInterval(-Double(elapsed))
            #expect(
                BrowserExtensionPromo.shouldShow(firstShown: shown, dismissed: false, now: now),
                "should still be up \(elapsed)s in"
            )
        }
    }

    @Test("It expires rather than waiting to be clicked")
    func expiresAtTheBoundary() {
        // Exactly a week is over: a banner nobody dismissed has still had its week.
        let exactly = now.addingTimeInterval(-BrowserExtensionPromo.window)
        #expect(
            BrowserExtensionPromo.shouldShow(firstShown: exactly, dismissed: false, now: now) == false
        )
        let after = now.addingTimeInterval(-BrowserExtensionPromo.window - 1)
        #expect(
            BrowserExtensionPromo.shouldShow(firstShown: after, dismissed: false, now: now) == false
        )
    }

    @Test("A clock that moved backwards does not extend the week forever")
    func futureStampDoesNotStick() {
        // Restoring a backup, or a corrected clock, can leave a stamp in the future. Without
        // the guard the elapsed time is negative — always inside the window — and the callout
        // would never expire on that machine.
        let future = now.addingTimeInterval(60 * 60 * 24 * 30)
        #expect(
            BrowserExtensionPromo.shouldShow(firstShown: future, dismissed: false, now: now) == false
        )
    }

    @Test("The window is a week, since that is what the disclosure promises")
    func windowIsSevenDays() {
        #expect(BrowserExtensionPromo.window == 7 * 24 * 60 * 60)
    }
}
