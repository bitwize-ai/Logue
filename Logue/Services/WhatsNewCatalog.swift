import Foundation

// MARK: - Types

/// Somewhere a card can send the reader, for a feature that does not live inside Logue.
struct WhatsNewLink: Equatable, Sendable {
    /// What the button says. A verb, so it is obvious the deck is not the destination.
    let label: String
    let url: URL
}

/// One thing worth telling the user about.
struct WhatsNewFeature: Identifiable, Equatable, Sendable {
    /// Stable slug. Never renamed and never reused — tests and screenshots pin to it.
    let id: String
    /// SF Symbol, shown when the card has no art.
    let symbol: String
    let title: String
    let detail: String
    /// Base names of PNGs in `Logue/Resources`, without the extension. Several play as a
    /// sequence, in the order written. See docs/WHATS_NEW.md.
    let screenshots: [String]
    /// Where to send the reader, for the few features that live outside the app.
    let link: WhatsNewLink?

    init(
        id: String,
        symbol: String,
        title: String,
        detail: String,
        screenshots: [String] = [],
        link: WhatsNewLink? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.screenshots = screenshots
        self.link = link
    }

    /// Convenience for the common case of a single still.
    init(
        id: String,
        symbol: String,
        title: String,
        detail: String,
        screenshot: String,
        link: WhatsNewLink? = nil
    ) {
        self.init(
            id: id, symbol: symbol, title: title, detail: detail,
            screenshots: [screenshot], link: link
        )
    }

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

/// Two lists, because they answer two questions: `tour` is "what is Logue for", `releases`
/// is "what changed". Features are defined once in `Feature` and composed into both, so
/// the copy cannot drift between them. See docs/WHATS_NEW.md.
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
            """,
            // Where it lives before what it does: the menu bar item is the part nobody
            // finds on their own.
            screenshots: ["whatsnew-asklogue-1-where", "whatsnew-asklogue-2-answer"]
        )

        /// Compile-time constant string — `URL(string:)` will never return nil.
        private static let chromeStore = URL(
            string: "https://chromewebstore.google.com/detail/logue/gaegipceeccdchdffamdphfiegfeenhc"
        )!

        // MARK: Recap, for the release deck only

        /// The back catalogue as two cards instead of four. An upgrading user already owns
        /// the app; re-teaching them transcription card by card buries the thing they opened
        /// the deck for. The tour still introduces these one at a time, because a newcomer
        /// has not seen any of it — the two lists exist to be different.
        static let recapCapture = WhatsNewFeature(
            id: "recap-capture",
            symbol: "waveform",
            title: "Everything you already had",
            detail: """
            Meetings that transcribe themselves from both sides of the call, Smart Minutes \
            and action items written from the transcript, and a real editor for the notes \
            that come out of it.
            """,
            screenshot: "whatsnew-transcription"
        )

        static let recapPrivacy = WhatsNewFeature(
            id: "recap-privacy",
            symbol: "lock.shield",
            title: "…and it never left your Mac",
            detail: """
            Transcription, summaries and search all run on this machine, on your own \
            models. Spaces and wiki-links keep the notes findable. Nothing is uploaded \
            unless you turn on a feature that says so.
            """,
            screenshot: "whatsnew-privacy"
        )

        static let chromeExtension = WhatsNewFeature(
            id: "chrome-extension",
            symbol: "puzzlepiece.extension.fill",
            title: "Bring the browser in too",
            detail: """
            The Logue extension puts the same chat and writing tools in any tab — ask \
            about the page you are on, and the answer comes from the model on this Mac \
            rather than from someone's server. Install it, take it for a spin, and tell \
            us how it goes: a review helps other people find it.
            """,
            screenshot: "whatsnew-chrome-extension",
            link: WhatsNewLink(label: UICopy.WhatsNew.chromeExtensionLink, url: chromeStore)
        )

        static let tasks = WhatsNewFeature(
            id: "tasks-and-triage",
            symbol: "checklist",
            title: "Tasks, and a way to triage them",
            detail: """
            Every action item Logue finds in a meeting lands somewhere you can actually \
            work: one list, with due dates, priorities and tags. Type "Send the deck \
            tomorrow #launch !" and it files itself.
            """
        )

        static let homeSurface = WhatsNewFeature(
            id: "home-agent-surface",
            symbol: "house",
            title: "One place to start",
            detail: """
            Home and Ask Logue were two screens doing one job. They are now a single \
            landing surface: your day, what to pick back up, and a prompt bar that turns \
            into the conversation without going anywhere else.
            """
        )

        static let recordingResilience = WhatsNewFeature(
            id: "recording-resilience",
            symbol: "shield.lefthalf.filled",
            title: "A recording that survives the worst",
            detail: """
            Unplug the headset mid-call, mute for ten minutes, or quit the app outright — \
            the recording keeps its place and the transcript comes back when Logue \
            reopens, instead of ending where the trouble started.
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
            """,
            screenshot: "whatsnew-wikilinks"
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

    /// What a first install is shown, once the onboarding wizard is done. Hand-picked
    /// rather than derived from `releases`, and it does not change every release — see
    /// docs/WHATS_NEW.md.
    static let tour: [WhatsNewFeature] = [
        Feature.meetings,
        Feature.smartMinutes,
        Feature.writingEditor,
        Feature.privacy,
        Feature.askLogue,
    ]

    // MARK: Upgrades

    /// What each release is worth announcing, ascending by version. A release lists only
    /// what it added; the first card must have art. See docs/WHATS_NEW.md.
    static let releases: [WhatsNewRelease] = [
        // 1.1.0 is a one-off: it introduces What's New, so it carries the whole back
        // catalogue rather than its own additions. Read in two halves — what Logue
        // already does, then what is new, which only means anything against the first.
        //
        // `crossApp` is deliberately not here. "Logue works in every other app too" is
        // true and is not what someone opening a release deck wants to be told: it asks
        // them to learn two shortcuts before they have used the thing in front of them.
        // It stays in the codebase and in the docs; it is the deck it does not earn.
        // `chromeExtension` is the one card that sends the reader somewhere else, which
        // is the point — the extension is not in this build and has to be installed.
        WhatsNewRelease(
            version: AppVersion(major: 1, minor: 1, patch: 0),
            features: [
                // The back catalogue, as two recap cards. It used to be eight, then four;
                // both were the same mistake in different sizes. Someone upgrading opened
                // this to find out what changed, and every card spent on what they already
                // use is one they click past to get there.
                Feature.recapCapture,
                Feature.recapPrivacy,
                // New — what these releases added, one card each. This is the half the deck
                // is for, so it is the half that gets the room.
                Feature.homeSurface,
                Feature.tasks,
                Feature.recordingResilience,
                Feature.chromeExtension,
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
    /// A name that does not resolve is dropped rather than left as a gap, so one missing
    /// file shortens a sequence instead of stalling it on a blank.
    static func screenshotURLs(for feature: WhatsNewFeature, in bundle: Bundle = .main) -> [URL] {
        feature.screenshots.compactMap { bundle.url(forResource: $0, withExtension: "png") }
    }
}
