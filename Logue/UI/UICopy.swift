import Foundation

/// Centralized consumer-tone microcopy for the chat-first surfaces.
///
/// This is a Swift namespace rather than a `.strings` bundle for now —
/// it gives compile-time safety on string IDs, easy refactoring, and a
/// single grep target ("`UICopy.`") to audit tone. We can move to
/// `Localizable.strings` when we ship a second language.
///
/// **Tone rules** (enforce on PR review):
/// - Warm, verb-first, never developer-y.
/// - 1–2 word buttons.
/// - Confirmations use the chosen verb ("Delete?" not "Are you sure?").
/// - Errors include a recovery action.
/// - Status varies with inferred work, not a constant "Thinking…".
enum UICopy {
    // MARK: - Empty states

    enum Empty {
        // The chat hero copy that used to live here went with `AgentChatEmptyState`. Home's
        // landing greets by time of day and derives its chips from the workspace, so there
        // is no fixed hero string left to name.

        static let dailyTipPrefix = "Try"
    }

    // MARK: - Input bar

    enum Input {
        static let placeholder = "Ask anything…"
        static let attach = "Attach"
        static let voice = "Dictate"
        static let send = "Send"
        static let stop = "Stop"
        static let webSearch = "Search"
        static let deepResearch = "Deep Research"
        static let reasoning = "Reasoning"
        static let footerPrivacy = "Local model · Offline-capable · No data leaves this Mac"
        static let charLimitNear = "Approaching context limit"
        static let charLimitOver = "Past context limit — older content will be trimmed"
    }

    // MARK: - Status (vary with inferred work — never static "Thinking…")

    enum Status {
        static let thinking = "Thinking…"
        static let reading = "Reading…"
        static let searching = "Searching the web…"
        static let drafting = "Drafting response…"
        static let analyzing = "Analyzing…"
        static let researching = "Researching…"
        static let summarizing = "Summarizing…"
        static let executing = "Running tool…"

        /// Pick a status string based on what the agent is currently doing.
        /// Falls back to "Thinking…" when no signal is available.
        static func describe(toolName: String?) -> String {
            guard let toolName else { return thinking }
            let lower = toolName.lowercased()
            if lower.contains("search") {
                return searching
            }
            if lower.contains("read") || lower.contains("get_") {
                return reading
            }
            if lower.contains("summar") {
                return summarizing
            }
            if lower.contains("research") {
                return researching
            }
            if lower.contains("analy") || lower.contains("detect") {
                return analyzing
            }
            if lower.contains("draft") || lower.contains("compose") || lower.contains("write") {
                return drafting
            }
            return executing
        }
    }

    // MARK: - Hover toolbar actions

    enum Action {
        static let copy = "Copy"
        static let copied = "Copied"
        static let regenerate = "Regenerate"
        static let edit = "Edit"
        static let editAndResend = "Edit & resend"
        static let branch = "Branch from here"
        static let readAloud = "Read aloud"
        static let stopReading = "Stop"
        static let thumbsUp = "Mark good"
        static let thumbsDown = "Mark bad"
        static let exportConversation = "Export conversation"
        static let pin = "Pin"
        static let unpin = "Unpin"
        static let archive = "Archive"
        static let restore = "Restore"
        static let rename = "Rename"
        static let delete = "Delete"
    }

    // MARK: - Confirmations

    enum Confirm {
        static let deleteConversation = "Delete this conversation?"
        static let deleteConversationDetail = "It'll be moved to Archived for 30 days, then permanently removed."
        static let archiveConversation = "Archive this conversation?"
        static let eraseAllData = "Erase all data on this Mac?"
        static let eraseAllDataDetail = "Hold to confirm. This removes every conversation, attachment, and indexed document."
    }

    // MARK: - Toasts

    enum Toast {
        static let copied = "Copied"
        static let saved = "Saved"
        static let exported = "Exported to Downloads"
        static let pinned = "Pinned"
        static let unpinned = "Unpinned"
        static let archived = "Archived"
        static let restored = "Restored"
        static let reminderCreated = "Reminder created"
        static let eventCreated = "Event added to calendar"
        static let modelSwitched = "Switched model"
    }

    // MARK: - Errors (always include a recovery action)

    enum Error {
        static let modelUnreachable = "Couldn't reach the model — try again?"
        static let networkOffline = "You're offline. Web tools will be skipped."
        static let attachmentTooLarge = "That file is too large. Try one under 25 MB."
        static let attachmentUnsupported = "Logue can't read that file type yet."
        static let permissionDenied = "Permission needed — open Settings to grant access."
        static let toolFailed = "That tool didn't run. Try rephrasing or skip the action."
        static let inferenceBusy = "The model is finishing a previous request — try again in a moment."
    }

    // MARK: - Trust signals

    enum Trust {
        static let local = "Local"
        static let onDevice = "On-device"
        static let networkUsed = "Network used"
        static let networkUsedDetail = "This response used a web tool. Other content stayed on your Mac."
        static let bannerFull = "Local model · Offline-capable · No data leaves this Mac"
    }

    // MARK: - Onboarding (3-card flow)

    enum Onboarding {
        static let card1Title = "Everything stays on your Mac"
        static let card1Subtitle = "No accounts, no cloud, no logs. Logue runs entirely on your device."
        static let card1Continue = "Sounds good"

        static let card2Title = "Pick a model"
        static let card2Subtitle = "Smaller models are faster; larger ones reason better. You can switch any time."
        static let card2Skip = "I'll set this up later"

        static let card3Title = "One-tap access, anywhere"
        static let card3Subtitle = "Press ⌥Space from any app to ask Logue. You can change this in Settings."
        static let card3Continue = "Let's go"
    }

    // MARK: - What's New / feature tour

    enum WhatsNew {
        /// Fresh install, after the onboarding wizard.
        static let discoverTitle = "Discover Logue"
        /// One or more releases the user has not seen yet.
        static let updatedTitle = "What's New"

        static let back = "Back"
        static let next = "Continue"
        static let skip = "Skip"
        /// Leaving release notes part-read. Every deck needs a way out that is not
        /// clicking through all of it.
        static let close = "Close"
        /// Last card of the first-run tour.
        static let finishTour = "Start using Logue"
        /// Last card of a release's notes.
        static let finishNotes = "Done"

        /// Badge on a notes card, so a user catching up across releases can tell
        /// which version brought what.
        static func versionBadge(_ version: String) -> String {
            "New in \(version)"
        }

        /// Help menu. Says where it goes, because it leaves the app.
        static let chromeExtensionMenuItem = "Get the Chrome Extension"
        /// The card's button. A verb, so the deck is plainly not the destination.
        static let chromeExtensionLink = "Get the Chrome extension"

        /// Help menu. Named for the app because it sits among app-wide items.
        static let menuItem = "What's New in Logue"
        /// Settings → General, beside "Show welcome tour".
        static let settingsButton = "What's New"
    }
}
