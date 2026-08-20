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

    @Test("An install that has not finished onboarding is owed nothing at launch")
    func freshInstallIsOwedNothing() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: nil,
            hasCompletedOnboarding: false,
            releases: catalog
        )
        // The tour belongs to the onboarding sheet's `onDismiss`, which is the only
        // thing that knows the wizard has actually gone. A second source for it here
        // would race that one to present the same sheet.
        #expect(presentation == .none)
    }

    @Test("A stamp does not turn a fresh install into release notes")
    func freshInstallIgnoresStamp() {
        let presentation = WhatsNewGate.presentation(
            current: version(1, 2, 0),
            lastSeen: version(1, 0, 0),
            hasCompletedOnboarding: false,
            releases: catalog
        )
        #expect(presentation == .none)
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

    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) throws {
        try LogueTests.withScratchDefaults(label: "WhatsNewGateTests", body)
    }

    @Test("Marking a version seen records it")
    func markSeenRecordsVersion() throws {
        try withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 1, 0), defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.1.0")
        }
    }

    @Test("The stamp only ever rises")
    func markSeenNeverLowersStamp() throws {
        try withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 2, 0), defaults: defaults)
            // Re-opening the notes on an older build must not make 1.2.0 unseen again.
            WhatsNewGate.markSeen(upTo: version(1, 0, 0), defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.2.0")
        }
    }

    @Test("Marking with no readable version leaves the stamp alone")
    func markSeenIgnoresNilVersion() throws {
        try withScratchDefaults { defaults in
            WhatsNewGate.markSeen(upTo: version(1, 1, 0), defaults: defaults)
            WhatsNewGate.markSeen(upTo: nil, defaults: defaults)
            let stored = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastSeenWhatsNewVersion)
            #expect(stored == "1.1.0")
        }
    }

    @Test("The stamp is what was shown, not what the build is")
    func stampRecordsOnlyWhatWasDisplayed() throws {
        // The Help menu and Settings open one release, not the whole backlog. Stamping
        // the running version there marks everything older as seen without showing it,
        // and because the stamp only rises those releases are gone for good.
        let shown = WhatsNewView.Mode.whatsNew([release(1, 1, 0)])
        #expect(shown.seenThrough == version(1, 1, 0))

        try withScratchDefaults { defaults in
            defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
            WhatsNewGate.markSeen(upTo: shown.seenThrough, defaults: defaults)

            // 1.2.0 was never displayed, so a 1.2.0 build must still offer it.
            let stillOwed = WhatsNewGate.presentation(
                current: version(1, 2, 0),
                lastSeen: version(1, 1, 0),
                hasCompletedOnboarding: true,
                releases: catalog
            )
            #expect(versions(of: stillOwed) == [version(1, 2, 0)])
        }
    }

    @Test("A deck spanning several releases stamps the newest of them")
    func stampCoversEveryReleaseShown() {
        let shown = WhatsNewView.Mode.whatsNew([release(1, 2, 0), release(1, 1, 0)])
        #expect(shown.seenThrough == version(1, 2, 0))
    }

    // `Mode.discover.seenThrough` is deliberately not tested here. It is defined as
    // `AppVersion.current`, so any assertion about it has to compute the expected value
    // with the expression under test — it would pass whatever that returned, including
    // nil. Making it falsifiable needs an injectable version on `Mode`, which is a
    // change to production shape for a test's benefit; the decision it encodes is
    // recorded on the property itself instead. The `.whatsNew` branch, which is the one
    // that can be got wrong, is covered above.

    // MARK: - The real catalog

    @Test("Releases are unique and ascending")
    func catalogIsOrdered() {
        let versions = WhatsNewCatalog.releases.map(\.version)
        #expect(versions == versions.sorted())
        #expect(Set(versions.map(\.description)).count == versions.count)
    }

    /// Every list a user can be shown: each release's deck, plus the first-run tour.
    private var allDecks: [[WhatsNewFeature]] {
        WhatsNewCatalog.releases.map(\.features) + [WhatsNewCatalog.tour]
    }

    @Test("No deck shows the same feature twice")
    func catalogFeaturesAreWellFormed() {
        for features in allDecks {
            #expect(!features.isEmpty)
            #expect(Set(features.map(\.id)).count == features.count)
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

    @Test("Every deck opens on a card that has art")
    func everyDeckOpensOnArt() {
        // The reported bug: What's New opened on a symbol-only card while every
        // screenshot sat several clicks behind it, which reads as the art being missing.
        for features in allDecks {
            guard let first = features.first else { continue }
            #expect(first.hasArt, "\(first.id) opens a deck with no art")
        }
    }

    @Test("A release's notes stay a deck, not a slideshow")
    func releaseNotesAreBounded() {
        let backCatalogue = AppVersion(major: 1, minor: 1, patch: 0)
        for release in WhatsNewCatalog.releases {
            // Only 1.1.0 carries the whole back catalogue, because it is the release that
            // introduces What's New. Anything else this long is listing more than it added.
            let cap = release.version == backCatalogue ? 13 : 6
            #expect(
                release.features.count <= cap,
                "\(release.version) has \(release.features.count) cards, cap is \(cap)"
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
        // `WhatsNewView.Mode.askedForByName()` falls back to the tour, not a blank sheet.
        let oldest = try #require(WhatsNewCatalog.releases.first)
        let before = AppVersion(major: oldest.version.major, minor: 0, patch: 0)
        #expect(before < oldest.version)
        #expect(WhatsNewCatalog.latestRelease(notNewerThan: before) == nil)
    }

    @Test("Asking for the notes by name offers the whole backlog, not just the newest")
    func askedForByNameOffersEveryUnseenRelease() throws {
        // The trap this closes: Settings → What's New showed exactly one release and
        // then stamped it, and the stamp only rises. A user two releases behind lost
        // the one in between — permanently, without it ever being drawn. Settings is
        // reachable from the menu bar while the launch deck is still up, and on a
        // launch where the main window never appears it is the first thing to touch
        // the stamp at all.
        try withScratchDefaults { defaults in
            // No stamp and onboarding done: the launch gate owes this user every
            // release the build is old enough to announce.
            defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
            let asked = WhatsNewView.Mode.askedForByName(defaults: defaults)

            switch WhatsNewGate.presentationForLaunch(defaults: defaults) {
            case let .whatsNew(owed):
                #expect(asked == .whatsNew(owed))
            case .none:
                // Nothing owed — this build predates the catalog, or its version is
                // unreadable. Asking by name then falls back to the newest notes, and
                // to the tour when there are none.
                let newest = WhatsNewCatalog.latestRelease(notNewerThan: AppVersion.current)
                #expect(asked == newest.map { WhatsNewView.Mode.whatsNew([$0]) } ?? .discover)
            }
        }
    }

    @Test("An unreadable build version opens the newest notes rather than nothing")
    func latestReleaseWithoutAVersion() throws {
        // Unlike the launch gate, this path is the user having asked by name. Showing
        // them the newest notes beats an empty sheet.
        let newest = try #require(WhatsNewCatalog.releases.last)
        #expect(WhatsNewCatalog.latestRelease(notNewerThan: nil) == newest)
    }

    @Test("Every named screenshot is actually in the bundle")
    func catalogScreenshotsResolve() {
        let features = allDecks.flatMap { $0 }.filter(\.hasArt)
        #expect(!features.isEmpty)
        for feature in features {
            // A typo degrades silently — to a symbol-only card, or to a sequence quietly
            // missing a step — so it needs a test rather than a convention.
            let named = feature.screenshots.count
            let found = WhatsNewCatalog.screenshotURLs(for: feature).count
            #expect(found == named, "\(feature.id) names \(named) images but only \(found) are in the bundle")
        }
    }

    @Test("A sequence is in a deliberate order, with no repeats")
    func sequencesAreWellFormed() {
        for feature in allDecks.flatMap({ $0 }) {
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
