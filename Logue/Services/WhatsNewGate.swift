import Foundation
import os.log

/// Decides what a launch owes the user: the first-run feature tour, the notes for
/// releases they have not seen, or nothing at all.
///
/// The decision is a pure function so every branch can be tested without touching
/// UserDefaults; `presentationForLaunch()` is the thin shell that reads the real state.
enum WhatsNewGate {
    enum Presentation: Equatable {
        /// Nothing to show. The common case for a user who is already up to date.
        case none
        /// A fresh install: a tour of what Logue does, shown once onboarding is finished.
        case discoverTour
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
        // A version we cannot read is not evidence of anything. Showing notes on a
        // guess would repeat them on every launch, so do nothing.
        guard let current else {
            logger.error("No parseable app version; skipping What's New")
            return .none
        }

        // Onboarding not done means nobody has used this copy of Logue yet. The tour
        // waits for the wizard to finish — the caller sequences that, not this.
        guard hasCompletedOnboarding else { return .discoverTour }

        let unseen = releases
            .filter { release in
                // The upper bound matters on development builds, where the catalog
                // routinely describes a version MARKETING_VERSION has not been bumped to.
                guard release.version <= current else { return false }
                // No stamp means nothing has ever been announced to this user — What's
                // New did not exist in 1.0.0, so an install from then has seen none of
                // it. That is "seen nothing", not "seen everything up to now".
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

    /// Records that the user has seen everything up to `version`.
    ///
    /// Only ever raises the stamp. Re-opening the notes from the Help menu, or running
    /// an older build against a newer stamp, must not make a release unseen again.
    ///
    /// Called when the sheet closes rather than when it opens: a crash between the two
    /// should cost a second showing, not swallow the release notes permanently.
    static func markSeen(upTo version: AppVersion? = AppVersion.current, defaults: UserDefaults = .standard) {
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
