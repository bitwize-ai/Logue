import Foundation
import Testing

@testable import Logue

/// What the deck actually says, as opposed to when it is shown — `WhatsNewGateTests` owns
/// the timing.
///
/// These pin the decisions that are easy to undo by accident: a card removed on purpose is
/// one edit away from coming back, and the one card that leaves the app is worth more than
/// a symbol and a sentence.
@Suite("WhatsNewCatalog")
struct WhatsNewCatalogTests {
    private var release110: WhatsNewRelease? {
        WhatsNewCatalog.releases.first { $0.version == AppVersion(major: 1, minor: 1, patch: 0) }
    }

    // MARK: - What 1.1.0 announces

    @Test("1.1.0 announces the three features that shipped with it")
    func releaseCoversWhatShipped() throws {
        let ids = try #require(release110).features.map(\.id)
        for expected in ["home-agent-surface", "tasks-and-triage", "recording-resilience"] {
            #expect(ids.contains(expected), "1.1.0 should announce \(expected)")
        }
    }

    /// Removed deliberately: it asks a reader to learn two shortcuts before they have used
    /// the thing in front of them. It is still a real feature and still in the docs — this
    /// guards the editorial call, which a single line would otherwise quietly reverse.
    @Test("The cross-app card is not in the release deck")
    func crossAppIsNotAnnounced() throws {
        #expect(try #require(release110).features.map(\.id).contains("cross-app") == false)
    }

    @Test("The back catalogue is two recap cards, not a re-teaching of the app")
    func backCatalogueIsCondensed() throws {
        let ids = try #require(release110).features.map(\.id)
        #expect(ids.prefix(2) == ["recap-capture", "recap-privacy"])

        // The individual back-catalogue cards belong to the tour now. Someone upgrading
        // opened this to find out what changed; every card spent on what they already use is
        // one they click past to get there.
        for retired in ["meeting-transcription", "smart-minutes", "writing-editor", "privacy"] {
            #expect(ids.contains(retired) == false, "\(retired) should not be in the release deck")
        }
    }

    @Test("Most of the deck is what this release added")
    func theNewHalfDominates() throws {
        let features = try #require(release110).features
        let recap = features.filter { $0.id.hasPrefix("recap-") }.count
        #expect(recap == 2)
        #expect(features.count - recap > recap, "the new half should be the bulk of the deck")
    }

    // MARK: - The card that leaves the app

    @Test("The Chrome extension card carries a link to the store listing")
    func chromeExtensionLinksOut() throws {
        let feature = try #require(
            release110?.features.first { $0.id == "chrome-extension" }
        )
        let link = try #require(feature.link, "the card exists to send the reader somewhere")

        // Not `contains("chromewebstore")`: a card that opened `http://` or some other host
        // would satisfy that and still be wrong.
        #expect(link.url.scheme == "https")
        #expect(link.url.host == "chromewebstore.google.com")
        #expect(link.label.isEmpty == false)
    }

    @Test("No other card sends the reader out of the app")
    func onlyTheExtensionLinksOut() {
        let linked = WhatsNewCatalog.releases
            .flatMap(\.features)
            .filter { $0.link != nil }
            .map(\.id)
        #expect(linked == ["chrome-extension"], "unexpected outbound links: \(linked)")
    }

    // MARK: - Shape

    @Test("The first card of a release has art, so the deck does not open on an icon")
    func firstCardIsIllustrated() throws {
        for release in WhatsNewCatalog.releases {
            let first = try #require(release.features.first)
            #expect(first.hasArt, "\(release.version) opens on \(first.id), which has none")
        }
    }

    @Test("Every id is unique, since ids are what tests and screenshots pin to")
    func idsAreUnique() {
        for release in WhatsNewCatalog.releases {
            let ids = release.features.map(\.id)
            #expect(Set(ids).count == ids.count, "duplicate id in \(release.version)")
        }
    }

    @Test("The first-run tour stays short and is not the upgrade deck")
    func tourIsItsOwnList() {
        // A newcomer handed the release deck gets a dozen cards for features they have no
        // context for. The two lists exist to be different lengths.
        #expect(WhatsNewCatalog.tour.count <= 6)
        #expect(WhatsNewCatalog.tour.count < (release110?.features.count ?? 0))
    }
}
