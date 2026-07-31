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
    /// Base name of a PNG in `Logue/Resources`, without the extension. Nil renders the
    /// card symbol-only, which is the ordinary case rather than a failure.
    let screenshot: String?

    init(id: String, symbol: String, title: String, detail: String, screenshot: String? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.screenshot = screenshot
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
    /// Deliberately short. A newcomer has just clicked through seven pages of setup, and
    /// the slide they close early is worth nothing — so this is the headlines only, and
    /// the rest of the app introduces itself when they get there.
    static let tour: [WhatsNewFeature] = [
        Feature.meetings,
        Feature.smartMinutes,
        Feature.writingEditor,
        Feature.askLogue,
        Feature.privacy,
    ]

    // MARK: Upgrades

    /// What each release is worth announcing, ascending by version.
    ///
    /// 1.0.1 carries the whole feature set rather than only what 1.0.1 added, because
    /// What's New did not exist in 1.0.0 — nothing has ever been announced to anyone, so
    /// for every existing user this is the first time any of it is being surfaced.
    /// Later releases list only their own additions.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: AppVersion(major: 1, minor: 0, patch: 1),
            features: [
                Feature.markdownStorage,
                Feature.wikiLinks,
                Feature.properties,
                Feature.savedViews,
                Feature.meetings,
                Feature.smartMinutes,
                Feature.writingEditor,
                Feature.askLogue,
                Feature.crossApp,
                Feature.spacesAndSearch,
                Feature.privacy,
                Feature.externalProviders,
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

    /// Where a feature's bundled screenshot lives, if it has one.
    ///
    /// Nil is ordinary rather than a failure: most features are illustrated by their
    /// symbol alone. A test walks the catalog to catch the case that is a failure —
    /// a name that no longer matches a file in the bundle.
    static func screenshotURL(for feature: WhatsNewFeature, in bundle: Bundle = .main) -> URL? {
        guard let name = feature.screenshot else { return nil }
        return bundle.url(forResource: name, withExtension: "png")
    }
}
