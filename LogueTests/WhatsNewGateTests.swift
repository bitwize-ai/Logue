import Foundation
@testable import Logue
import Testing

/// Covers what a launch decides to show. The cases that matter are the ones where
/// getting it wrong is loud: replaying notes every launch, or greeting a long-time
/// user with a tour of features they already use.
@Suite("WhatsNewGate")
struct WhatsNewGateTests {
    // MARK: - Fixtures

    private func version(_ major: Int, _ minor: Int, _ patch: Int) -> AppVersion {
        AppVersion(major: major, minor: minor, patch: patch)
    }

    private func release(_ major: Int, _ minor: Int, _ patch: Int) -> WhatsNewRelease {
        let name = "\(major).\(minor).\(patch)"
        return WhatsNewRelease(
            version: version(major, minor, patch),
            features: [
                WhatsNewFeature(
                    id: "feature-\(name)",
                    symbol: "star",
                    title: "Feature \(name)",
                    detail: "What \(name) added."
                ),
            ]
        )
    }

    /// Three consecutive releases — enough to exercise skipping one and clamping past one.
    private var catalog: [WhatsNewRelease] {
        [release(1, 0, 0), release(1, 1, 0), release(1, 2, 0)]
    }

    private func versions(of presentation: WhatsNewGate.Presentation) -> [AppVersion] {
        guard case let .whatsNew(releases) = presentation else { return [] }
        return releases.map(\.version)
    }

    // MARK: - Fresh install

    @Test("An install that has not finished onboarding gets the tour")
    func freshInstallGetsTour() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: nil,
            hasCompletedOnboarding: false,
            releases: catalog
        )
        #expect(presentation == .discoverTour)
    }

    @Test("A stamp does not turn the tour into release notes before onboarding is done")
    func freshInstallIgnoresStamp() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: version(1, 0, 0),
            hasCompletedOnboarding: false,
            releases: catalog
        )
        #expect(presentation == .discoverTour)
    }

    // MARK: - Bootstrap (installs predating this feature)

    @Test("An onboarded user with no stamp gets the delta, not the tour")
    func unstampedOnboardedUserGetsDelta() {
        // Someone who has run 1.0.0 for months. The tour would insult them; the notes
        // for what 1.1.0 added are the point.
        let presentation = WhatsNewGate.presentation(
            current: version(1, 1, 0),
            lastSeen: nil,
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(versions(of: presentation) == [version(1, 1, 0)])
    }

    @Test("An onboarded user with no stamp on the oldest release sees nothing")
    func unstampedOnboardedUserOnOldestReleaseSeesNothing() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 0, 0),
            lastSeen: nil,
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(presentation == .none)
    }

    // MARK: - Upgrades

    @Test("Skipping a release shows both, newest first")
    func skippedReleasesAreCombined() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: version(1, 0, 0),
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(versions(of: presentation) == [version(1, 2, 0), version(1, 1, 0)])
    }

    @Test("A release newer than this build is not announced by it")
    func clampsToCurrentBuild() {
        // A development build whose MARKETING_VERSION lags the catalog.
        let presentation = WhatsNewGate.presentation(
            current: version(1, 1, 0),
            lastSeen: version(1, 0, 0),
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(versions(of: presentation) == [version(1, 1, 0)])
    }

    // MARK: - Nothing to say

    @Test("An up-to-date user sees nothing")
    func upToDateSeesNothing() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: version(1, 2, 0),
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(presentation == .none)
    }

    @Test("Running an older build than the stamp shows nothing")
    func downgradeSeesNothing() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 1, 0),
            lastSeen: version(1, 2, 0),
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(presentation == .none)
    }

    @Test("An unreadable app version shows nothing rather than guessing")
    func unparseableVersionSeesNothing() {
        let presentation = WhatsNewGate.presentation(
            current: nil,
            lastSeen: version(1, 0, 0),
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(presentation == .none)
    }

    @Test("An empty catalog shows nothing")
    func emptyCatalogSeesNothing() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: nil,
            hasCompletedOnboarding: true,
            releases: []
        )
        #expect(presentation == .none)
    }

    // MARK: - Stamp

    /// A scratch defaults suite, so tests never touch the real preferences.
    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "WhatsNewGateTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test("Marking a version seen records it")
    func markSeenRecordsVersion() {
        withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 1, 0), defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.1.0")
        }
    }

    @Test("The stamp only ever rises")
    func markSeenNeverLowersStamp() {
        withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 2, 0), defaults: defaults)
            // Re-opening the notes on an older build must not make 1.2.0 unseen again.
            WhatsNewGate.markSeen(upTo: version(1, 0, 0), defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.2.0")
        }
    }

    @Test("Marking with no readable version leaves the stamp alone")
    func markSeenIgnoresNilVersion() {
        withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 1, 0), defaults: defaults)
            WhatsNewGate.markSeen(upTo: nil, defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.1.0")
        }
    }

    @Test("A stamped, onboarded user is read back as having nothing to see")
    func launchReadsStoredStamp() {
        withScratchDefaults { defaults in
            defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
            WhatsNewGate.markSeen(upTo: AppVersion.current, defaults: defaults)
            #expect(WhatsNewGate.presentationForLaunch(defaults: defaults) == .none)
        }
    }

    // MARK: - The real catalog

    @Test("Releases are unique and ascending")
    func catalogIsOrdered() {
        let versions = WhatsNewCatalog.releases.map(\.version)
        #expect(versions == versions.sorted())
        #expect(Set(versions.map(\.description)).count == versions.count)
    }

    @Test("The oldest catalogued release is 1.0.0")
    func catalogStartsAtFirstShippedRelease() {
        // The gate uses this as the baseline for users who upgrade from before the
        // feature existed. Dropping the 1.0.0 block would silently shift it and start
        // announcing 1.0.0 features to people who have had them all along.
        #expect(WhatsNewCatalog.releases.first?.version == AppVersion(major: 1, minor: 0, patch: 0))
    }

    @Test("Every feature has a unique id and something to say")
    func catalogFeaturesAreWellFormed() {
        let features = WhatsNewCatalog.releases.flatMap(\.features)
        #expect(!features.isEmpty)
        #expect(Set(features.map(\.id)).count == features.count)
        for feature in features {
            #expect(!feature.title.isEmpty)
            #expect(!feature.detail.isEmpty)
            #expect(!feature.symbol.isEmpty)
        }
    }

    @Test("The first-run tour is a highlights reel, not the whole catalog")
    func tourIsBounded() {
        let tour = WhatsNewCatalog.tourFeatures
        #expect(!tour.isEmpty)
        // A fresh install has just finished the onboarding wizard; a long second
        // slideshow is how a tour gets skipped.
        #expect(tour.count <= 8)
    }

    @Test("Every named screenshot is actually in the bundle")
    func catalogScreenshotsResolve() {
        let features = WhatsNewCatalog.releases.flatMap(\.features).filter { $0.screenshot != nil }
        #expect(!features.isEmpty)
        for feature in features {
            // A typo here degrades silently to a symbol-only card, so it needs a test.
            #expect(
                WhatsNewCatalog.screenshotURL(for: feature) != nil,
                "Missing bundled screenshot \(feature.screenshot ?? "") for \(feature.id)"
            )
        }
    }

    // MARK: - Reset

    @MainActor
    @Test("Resetting application data keeps the version stamp")
    func resetPreservesStamp() {
        // Otherwise a reset looks like a fresh install and replays every release note.
        #expect(
            TroubleshootingActions.preservedDefaultsKeys
                .contains(AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
        )
        #expect(
            TroubleshootingActions.preservedDefaultsKeys
                .contains(AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
        )
    }
}
