import Foundation
import os.log

/// Decides what a launch owes the user: the first-run feature tour, the notes for
/// releases they have not seen, or nothing at all.
///
/// The decision is a pure function so every branch can be tested without touching
/// UserDefaults; `presentationForLaunch()` is the thin shell that reads the real state.
enum WhatsNewGate {
    enum Presentation: Equatable {
        /// Nothing to show.
        case none
        /// Releases this user has not seen, newest first.
        case whatsNew([WhatsNewRelease])
    }

    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "WhatsNew")

    // MARK: - Decision

    /// - Parameters:
    ///   - current: the running build's version; nil when Info.plist is unparseable.
    ///   - lastSeen: the stored stamp, nil when there is none.
    ///   - hasCompletedOnboarding: doubles as "this is not a brand new install".
    ///   - releases: the catalog, ascending by version.
    static func presentation(
        current: AppVersion?,
        lastSeen: AppVersion?,
        hasCompletedOnboarding: Bool,
        releases: [WhatsNewRelease]
    ) -> Presentation {
        // A fresh install is owed the tour, not release notes — and the tour is not this
        // function's to hand out. It has to be sequenced after the onboarding wizard's
        // sheet has actually gone, which only that sheet's `onDismiss` knows; returning
        // a `.discoverTour` here would be a second, earlier source for the same sheet
        // and the two would race to present it.
        guard hasCompletedOnboarding else { return .none }

        // Guessing would replay the notes on every launch.
        guard let current else {
            logger.error("No parseable app version; skipping What's New")
            return .none
        }

        let unseen = releases
            .filter { release in
                // Development builds routinely run a catalog describing a version the
                // build itself has not been bumped to yet.
                guard release.version <= current else { return false }
                // No stamp means nothing was ever announced — What's New did not exist in
                // 1.0.0 — which is "seen nothing", not "seen everything up to now".
                guard let lastSeen else { return true }
                return release.version > lastSeen
            }
            .sorted { $0.version > $1.version }

        return unseen.isEmpty ? .none : .whatsNew(unseen)
    }

    /// Reads the real state and decides. Call once per launch.
    static func presentationForLaunch(defaults: UserDefaults = .standard) -> Presentation {
        presentation(
            current: AppVersion.current,
            lastSeen: storedVersion(in: defaults),
            hasCompletedOnboarding: defaults.bool(forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding),
            releases: WhatsNewCatalog.releases
        )
    }

    // MARK: - Stamp

    /// Records that the user has seen everything up to `version`, which must be what was
    /// actually shown — defaulting it to the running version silently buries the releases
    /// in between, and the stamp only ever rises.
    static func markSeen(upTo version: AppVersion?, defaults: UserDefaults = .standard) {
        guard let version else { return }
        if let stored = storedVersion(in: defaults), stored >= version {
            return
        }
        defaults.set(version.description, forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
    }

    private static func storedVersion(in defaults: UserDefaults) -> AppVersion? {
        defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            .flatMap(AppVersion.init)
    }
}
