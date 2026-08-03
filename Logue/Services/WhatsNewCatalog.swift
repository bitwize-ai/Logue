import Foundation

// MARK: - Types

/// One thing worth telling the user about.
struct WhatsNewFeature: Identifiable, Equatable, Sendable {
    /// Stable slug. Never renamed and never reused — tests and screenshots pin to it.
    let id: String
    /// SF Symbol shown as the card's hero.
    let symbol: String
    let title: String
    let detail: String
    /// Base names of PNGs in `Logue/Resources`, without the extension.
    ///
    /// Empty renders the card symbol-only, which is the ordinary case rather than a
    /// failure. One renders a still. More than one plays as a sequence, in the order
    /// written — which is what lets a card show *where* a feature lives before showing
    /// what it does: the menu it hides under, then the result. A still cannot say that.
    let screenshots: [String]

    /// A feature with one still, or none.
    init(id: String, symbol: String, title: String, detail: String, screenshot: String? = nil) {
        self.init(id: id, symbol: symbol, title: title, detail: detail, screenshots: screenshot.map { [$0] } ?? [])
    }

    /// A feature whose art is a sequence. Order is the order it plays.
    init(id: String, symbol: String, title: String, detail: String, screenshots: [String]) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.screenshots = screenshots
    }

    /// Whether this card has any art at all. Decks are ordered so these come first.
    var hasArt: Bool {
        !screenshots.isEmpty
    }
}

/// What one release added, in the order it should be read.
struct WhatsNewRelease: Equatable, Sendable {
    let version: AppVersion
    let features: [WhatsNewFeature]
}

// MARK: - Catalog

/// What to tell users about, kept as two separate lists because they answer two
/// different questions.
///
/// `tour` is for somebody who has never opened Logue: the headlines, in the order that
/// best explains what the app is for. `releases` is for somebody upgrading: what changed
/// since the version they last saw. A feature can appear in both, in neither, or in one
/// — deriving either list from the other always ended up compromising both.
///
/// Features are defined once in `Feature` and composed into the two lists, so the copy
/// cannot drift between them.
enum WhatsNewCatalog {
    // MARK: Features

    private enum Feature {
        static let meetings = WhatsNewFeature(
            id: "meeting-transcription",
            symbol: "waveform",
            title: "Meetings transcribe themselves",
            detail: """
            Logue hears both your microphone and the meeting audio, so it works in any \
            call without a bot joining the room. Transcription runs on your Mac as \
            people speak, and it tells who said what.
            """,
            screenshot: "whatsnew-transcription"
        )

        static let smartMinutes = WhatsNewFeature(
            id: "smart-minutes",
            symbol: "list.bullet.clipboard",
            title: "Minutes and action items, written for you",
            detail: """
            Every recording turns into a summary with the decisions and the follow-ups \
            pulled out. Action items collect in one place so nothing agreed in a meeting \
            quietly disappears after it.
            """,
            screenshot: "whatsnew-smart-minutes"
        )

        static let writingEditor = WhatsNewFeature(
            id: "writing-editor",
            symbol: "square.and.pencil",
            title: "An editor that helps you write",
            detail: """
            Rewrite a sentence, fix the grammar, change the tone, or check a claim — \
            without leaving the document. Tables, diagrams and equations render inline, \
            and anything you write can be exported as PDF or slides.
            """,
            screenshot: "whatsnew-writing-editor"
        )

        static let askLogue = WhatsNewFeature(
            id: "ask-logue",
            symbol: "sparkles",
            title: "Ask Logue about your own work",
            detail: """
            A chat that can actually reach your meetings, documents, calendar and \
            reminders, and take multiple steps to answer. It asks before it does \
            anything you would want to be asked about.
            """
        )

        static let crossApp = WhatsNewFeature(
            id: "cross-app",
            symbol: "command",
            title: "Logue works in every other app too",
            detail: """
            Press ⌘⌃I to rewrite whatever you have selected, anywhere in macOS, or \
            ⌥Space to ask a question without switching windows.
            """
        )

        static let spacesAndSearch = WhatsNewFeature(
            id: "spaces-and-search",
            symbol: "square.grid.2x2",
            title: "Spaces, and a search that understands you",
            detail: """
            Organise work into nested spaces, jump anywhere with ⌘K, and find things by \
            what you meant rather than the exact words you used.
            """,
            screenshot: "whatsnew-spaces"
        )

        static let privacy = WhatsNewFeature(
            id: "on-device-privacy",
            symbol: "lock.shield.fill",
            title: "None of it leaves your Mac",
            detail: """
            Models run on your own hardware and your notes are encrypted on disk. Logue \
            can also flag personal information before you share something. Web search and \
            outside AI providers exist, are off, and stay off until you turn them on.
            """,
            screenshot: "whatsnew-privacy"
        )

        static let externalProviders = WhatsNewFeature(
            id: "external-providers",
            symbol: "cpu",
            title: "Bring your own model",
            detail: """
            Point Logue at OpenAI, Anthropic, OpenRouter, Ollama or LM Studio when you \
            want a bigger model than your Mac can hold. Your key stays in the Keychain.
            """
        )

        static let markdownStorage = WhatsNewFeature(
            id: "markdown-storage",
            symbol: "doc.plaintext",
            title: "Keep your documents as plain markdown",
            detail: """
            Store documents as ordinary .md files in ~/Logue and edit them in any editor, \
            track them in git, or point another tool at them. The folder is the storage, \
            not a copy — edits, renames and moves flow both ways. Off by default, and \
            Logue explains what encryption you give up before you turn it on.
            """
        )

        static let wikiLinks = WhatsNewFeature(
            id: "wiki-links",
            symbol: "link",
            title: "Link documents with [[double brackets]]",
            detail: """
            Type [[ to link another document. Links show the target's real name, survive \
            renames, and every document lists what points back to it.
            """
        )

        static let properties = WhatsNewFeature(
            id: "properties-relationships",
            symbol: "tablecells",
            title: "Properties and relationships",
            detail: """
            Give documents typed fields — text, number, date, select, checkbox — and named \
            links to one another, all editable from a side panel.
            """
        )

        static let whatsNew = WhatsNewFeature(
            id: "whats-new",
            symbol: "gift",
            title: "Logue now tells you what changed",
            detail: """
            After an update, Logue shows what that release added — and only the versions \
            you have not already seen. You can reopen this any time from Help → What's New.
            """
        )

        static let savedViews = WhatsNewFeature(
            id: "saved-views-inbox",
            symbol: "tray.full",
            title: "Saved views and an inbox",
            detail: """
            Save any filter as a sidebar entry, and clear unfiled documents from the inbox \
            with keyboard-driven bulk actions.
            """
        )
    }

    // MARK: New installs

    /// What a first install is shown, once the onboarding wizard is done.
    ///
    /// Deliberately short, and deliberately hand-picked rather than derived from
    /// `releases`. A newcomer has just clicked through seven pages of setup, and the slide
    /// they close early is worth nothing — so this is the headlines only, and the rest of
    /// the app introduces itself when they get there. Handing them the upgrade deck
    /// instead would be a dozen cards of features they have no context for yet.
    ///
    /// Because it is hand-picked, it does not change when a release ships. Revisit it only
    /// when something lands that changes what Logue *is* — not for every addition.
    ///
    /// Illustrated cards first, same as the release decks, and it closes on Ask Logue —
    /// the one a newcomer can go and try the moment the sheet is gone.
    static let tour: [WhatsNewFeature] = [
        Feature.meetings,
        Feature.smartMinutes,
        Feature.writingEditor,
        Feature.privacy,
        Feature.askLogue,
    ]

    // MARK: Upgrades

    /// What each release is worth announcing, ascending by version.
    ///
    /// **1.1.0 is a one-off and must not be copied as the pattern.** It carries the whole
    /// feature set rather than only what 1.1.0 added, because 1.1.0 is the release that
    /// introduces What's New: nothing has ever been announced in-app, so for every user
    /// arriving from 1.0.0 or 1.0.1 this is the first time any of it is surfaced. Every
    /// release after it lists only its own additions, which is a handful of cards.
    ///
    /// Read in two halves: what Logue already does, then what is actually new. Someone
    /// arriving from 1.0.x is meeting both at once, and the second half only means
    /// anything against the first.
    ///
    /// Within the first half the illustrated cards lead, so the deck opens on art rather
    /// than on a bare symbol — which reads as the screenshots being broken.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: AppVersion(major: 1, minor: 1, patch: 0),
            features: [
                // Already there — what Logue is.
                Feature.meetings,
                Feature.smartMinutes,
                Feature.writingEditor,
                Feature.spacesAndSearch,
                Feature.privacy,
                Feature.askLogue,
                Feature.crossApp,
                Feature.externalProviders,
                // New — what these releases added.
                Feature.markdownStorage,
                Feature.wikiLinks,
                Feature.properties,
                Feature.savedViews,
                Feature.whatsNew,
            ]
        ),
    ]

    // MARK: - Queries

    /// The newest release this build actually is.
    ///
    /// For the Help menu and Settings, where the user asked to see the notes rather than
    /// being shown them. Bounded by the running version for the same reason the launch
    /// gate is: a development build should not advertise a release that does not exist.
    static func latestRelease(notNewerThan current: AppVersion?) -> WhatsNewRelease? {
        guard let current else { return releases.last }
        return releases.last { $0.version <= current }
    }

    /// Where a feature's bundled art lives, in play order.
    ///
    /// Empty is ordinary rather than a failure: most features are illustrated by their
    /// symbol alone. A test walks the catalog to catch the case that *is* a failure — a
    /// name that no longer matches a file in the bundle.
    ///
    /// A name that does not resolve is dropped rather than left as a gap, so one missing
    /// file degrades a three-step sequence to two steps instead of stalling on a blank.
    static func screenshotURLs(for feature: WhatsNewFeature, in bundle: Bundle = .main) -> [URL] {
        feature.screenshots.compactMap { bundle.url(forResource: $0, withExtension: "png") }
    }

    /// Whether every name this feature declares resolves to a bundled file. Used by the
    /// test that catches a typo, which would otherwise degrade silently.
    static func allScreenshotsResolve(for feature: WhatsNewFeature, in bundle: Bundle = .main) -> Bool {
        screenshotURLs(for: feature, in: bundle).count == feature.screenshots.count
    }
}
