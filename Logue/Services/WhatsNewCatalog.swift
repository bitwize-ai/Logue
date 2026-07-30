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
    /// Whether the first-run "Discover Logue" tour includes this feature.
    ///
    /// Every feature appears in its release's notes; only headline ones earn a card on
    /// day one, because a fresh install has already sat through the onboarding wizard.
    let inTour: Bool

    init(
        id: String,
        symbol: String,
        title: String,
        detail: String,
        screenshot: String? = nil,
        inTour: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.screenshot = screenshot
        self.inTour = inTour
    }
}

/// What one release added, in the order it should be read.
struct WhatsNewRelease: Equatable, Sendable {
    let version: AppVersion
    let features: [WhatsNewFeature]
}

// MARK: - Catalog

/// What shipped when.
///
/// Appending a block here is the whole job of announcing a release in-app; the sheet,
/// the gating and the first-run tour all read from this one list. Keep it ascending by
/// version — `WhatsNewGate` treats the first entry as the oldest release it knows about,
/// which is the baseline it assumes for users upgrading from before this feature existed.
enum WhatsNewCatalog {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: AppVersion(major: 1, minor: 0, patch: 0),
            features: [
                WhatsNewFeature(
                    id: "meeting-transcription",
                    symbol: "waveform",
                    title: "Meetings transcribe themselves",
                    detail: """
                    Logue hears both your microphone and the meeting audio, so it works in any \
                    call without a bot joining the room. Transcription runs on your Mac as \
                    people speak, and it tells who said what.
                    """,
                    screenshot: "whatsnew-transcription",
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "smart-minutes",
                    symbol: "list.bullet.clipboard",
                    title: "Minutes and action items, written for you",
                    detail: """
                    Every recording turns into a summary with the decisions and the follow-ups \
                    pulled out. Action items collect in one place so nothing agreed in a meeting \
                    quietly disappears after it.
                    """,
                    screenshot: "whatsnew-smart-minutes",
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "writing-editor",
                    symbol: "square.and.pencil",
                    title: "An editor that helps you write",
                    detail: """
                    Rewrite a sentence, fix the grammar, change the tone, or check a claim — \
                    without leaving the document. Tables, diagrams and equations render inline, \
                    and anything you write can be exported as PDF or slides.
                    """,
                    screenshot: "whatsnew-writing-editor",
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "ask-logue",
                    symbol: "sparkles",
                    title: "Ask Logue about your own work",
                    detail: """
                    A chat that can actually reach your meetings, documents, calendar and \
                    reminders, and take multiple steps to answer. It asks before it does \
                    anything you would want to be asked about.
                    """,
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "cross-app",
                    symbol: "command",
                    title: "Logue works in every other app too",
                    detail: """
                    Press ⌘⌃I to rewrite whatever you have selected, anywhere in macOS, or \
                    ⌥Space to ask a question without switching windows.
                    """,
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "spaces-and-search",
                    symbol: "square.grid.2x2",
                    title: "Spaces, and a search that understands you",
                    detail: """
                    Organise work into nested spaces, jump anywhere with ⌘K, and find things by \
                    what you meant rather than the exact words you used.
                    """,
                    screenshot: "whatsnew-spaces",
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "on-device-privacy",
                    symbol: "lock.shield.fill",
                    title: "None of it leaves your Mac",
                    detail: """
                    Models run on your own hardware and your notes are encrypted on disk. Logue \
                    can also flag personal information before you share something. Web search and \
                    outside AI providers exist, are off, and stay off until you turn them on.
                    """,
                    screenshot: "whatsnew-privacy",
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "external-providers",
                    symbol: "cpu",
                    title: "Bring your own model",
                    detail: """
                    Point Logue at OpenAI, Anthropic, OpenRouter, Ollama or LM Studio when you \
                    want a bigger model than your Mac can hold. Your key stays in the Keychain.
                    """
                ),
            ]
        ),
        WhatsNewRelease(
            version: AppVersion(major: 1, minor: 1, patch: 0),
            features: [
                WhatsNewFeature(
                    id: "markdown-storage",
                    symbol: "doc.plaintext",
                    title: "Keep your documents as plain markdown",
                    detail: """
                    Store documents as ordinary .md files in ~/Logue and edit them in any editor, \
                    track them in git, or point another tool at them. The folder is the storage, \
                    not a copy — edits, renames and moves flow both ways. Off by default, and \
                    Logue explains what encryption you give up before you turn it on.
                    """,
                    inTour: true
                ),
                WhatsNewFeature(
                    id: "wiki-links",
                    symbol: "link",
                    title: "Link documents with [[double brackets]]",
                    detail: """
                    Type [[ to link another document. Links show the target's real name, survive \
                    renames, and every document lists what points back to it.
                    """
                ),
                WhatsNewFeature(
                    id: "properties-relationships",
                    symbol: "tablecells",
                    title: "Properties and relationships",
                    detail: """
                    Give documents typed fields — text, number, date, select, checkbox — and named \
                    links to one another, all editable from a side panel.
                    """
                ),
                WhatsNewFeature(
                    id: "saved-views-inbox",
                    symbol: "tray.full",
                    title: "Saved views and an inbox",
                    detail: """
                    Save any filter as a sidebar entry, and clear unfiled documents from the inbox \
                    with keyboard-driven bulk actions.
                    """
                ),
            ]
        ),
    ]

    // MARK: - Queries

    /// The headline features, oldest release first — the first-run "Discover Logue" tour.
    static var tourFeatures: [WhatsNewFeature] {
        releases.flatMap(\.features).filter(\.inTour)
    }

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
