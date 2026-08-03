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

    @Test("An onboarded user with no stamp is told everything, not nothing")
    func unstampedOnboardedUserSeesEverything() {
        // What's New did not exist in 1.0.0, so an install from then has been shown
        // none of it. Assuming otherwise would silently skip every existing user.
        let presentation = WhatsNewGate.presentation(
            current: version(1, 1, 0),
            lastSeen: nil,
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(versions(of: presentation) == [version(1, 1, 0), version(1, 0, 0)])
    }

    @Test("An unstamped user on the oldest release still sees that release")
    func unstampedOnboardedUserOnOldestReleaseSeesIt() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 0, 0),
            lastSeen: nil,
            hasCompletedOnboarding: true,
            releases: catalog
        )
        #expect(versions(of: presentation) == [version(1, 0, 0)])
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

    @Test("Every feature has a unique id and something to say")
    func catalogFeaturesAreWellFormed() {
        for features in WhatsNewCatalog.releases.map(\.features) + [WhatsNewCatalog.tour] {
            #expect(!features.isEmpty)
            // Within one list, a repeated feature would show the same card twice.
            #expect(Set(features.map(\.id)).count == features.count)
            for feature in features {
                #expect(!feature.title.isEmpty)
                #expect(!feature.detail.isEmpty)
                #expect(!feature.symbol.isEmpty)
            }
        }
    }

    @Test("The first-run tour is a highlights reel, not the whole catalog")
    func tourIsBounded() {
        let tour = WhatsNewCatalog.tour
        #expect(!tour.isEmpty)
        // A fresh install has just finished the onboarding wizard; a long second
        // slideshow is how a tour gets skipped.
        #expect(tour.count <= 6)
    }

    @Test("Every deck opens on the cards that have art")
    func illustratedFeaturesLeadEveryDeck() {
        // The reported bug: What's New opened on four symbol-only cards and every
        // screenshot sat behind them, which reads as the screenshots being missing.
        // Ordering art-first is the fix, so it is the thing worth pinning.
        for features in WhatsNewCatalog.releases.map(\.features) + [WhatsNewCatalog.tour] {
            let firstWithoutArt = features.firstIndex { !$0.hasArt }
            let lastWithArt = features.lastIndex(where: \.hasArt)
            guard let firstWithoutArt, let lastWithArt else { continue }
            let illustrated = features[lastWithArt].id
            let bare = features[firstWithoutArt].id
            #expect(
                firstWithoutArt > lastWithArt,
                "\(illustrated) has a screenshot but sits behind \(bare), which has none"
            )
        }
    }

    @Test("A release's notes stay a deck, not a slideshow")
    func releaseNotesAreBounded() {
        for release in WhatsNewCatalog.releases {
            // 1.1.0 is the ceiling on purpose: it is the one release that carries the
            // whole back catalogue, because it is the one that introduces What's New.
            // Anything longer than that is a release listing more than it added.
            #expect(
                release.features.count <= 13,
                "\(release.version) has \(release.features.count) cards"
            )
        }
    }

    // MARK: - What the Help menu opens

    @Test("The Help menu opens the newest release this build actually is")
    func latestReleaseIsBoundedByBuild() throws {
        let newest = try #require(WhatsNewCatalog.releases.last)
        #expect(WhatsNewCatalog.latestRelease(notNewerThan: newest.version) == newest)
        // A development build whose MARKETING_VERSION lags the catalog must not
        // advertise a release that has not been tagged.
        let ahead = AppVersion(major: newest.version.major, minor: newest.version.minor + 1, patch: 0)
        #expect(WhatsNewCatalog.latestRelease(notNewerThan: ahead) == newest)
    }

    @Test("A build older than every catalogued release has no notes to open")
    func latestReleaseIsNilBeforeTheFirstRelease() throws {
        // True of the shipping catalog on any 1.0.x build: What's New arrives in 1.1.0,
        // so there is nothing for it to open until MARKETING_VERSION says 1.1.0.
        // `WhatsNewView.Mode.latestNotes` falls back to the tour rather than a blank sheet.
        let oldest = try #require(WhatsNewCatalog.releases.first)
        let before = AppVersion(major: oldest.version.major, minor: 0, patch: 0)
        #expect(before < oldest.version)
        #expect(WhatsNewCatalog.latestRelease(notNewerThan: before) == nil)
    }

    @Test("An unreadable build version opens the newest notes rather than nothing")
    func latestReleaseWithoutAVersion() {
        // Unlike the launch gate, this path is the user having asked by name. Showing
        // them the newest notes beats an empty sheet.
        #expect(
            WhatsNewCatalog.latestRelease(notNewerThan: nil)?.version
                == WhatsNewCatalog.releases.last?.version
        )
    }

    @Test("Every named screenshot is actually in the bundle")
    func catalogScreenshotsResolve() {
        let features = (WhatsNewCatalog.releases.flatMap(\.features) + WhatsNewCatalog.tour)
            .filter(\.hasArt)
        #expect(!features.isEmpty)
        for feature in features {
            // A typo degrades silently — to a symbol-only card, or to a sequence quietly
            // missing a step — so it needs a test rather than a convention.
            let named = feature.screenshots.count
            let found = WhatsNewCatalog.screenshotURLs(for: feature).count
            #expect(
                WhatsNewCatalog.allScreenshotsResolve(for: feature),
                "\(feature.id) names \(named) images but only \(found) are in the bundle"
            )
        }
    }

    @Test("A sequence is in a deliberate order, with no repeats")
    func sequencesAreWellFormed() {
        for feature in WhatsNewCatalog.releases.flatMap(\.features) + WhatsNewCatalog.tour {
            // The same frame twice in one sequence reads as the animation being stuck.
            #expect(
                Set(feature.screenshots).count == feature.screenshots.count,
                "\(feature.id) repeats a frame"
            )
            // Past about four steps a card stops being a card and becomes a video the
            // user cannot pause.
            #expect(feature.screenshots.count <= 4, "\(feature.id) has too many steps")
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
