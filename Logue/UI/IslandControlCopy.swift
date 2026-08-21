import Foundation

/// What each of the island's controls is called, and what it says about its state.
///
/// Almost every control in the island carried only `.help(…)`. On macOS that becomes the
/// accessibility *hint*, not the label — so VoiceOver fell back to the only other thing it
/// had, the SF Symbol name. The send button announced "arrow up", the close button announced
/// "xmark", and the two toggles announced nothing at all about being on, which is the single
/// thing a toggle exists to convey.
///
/// A label is not the tooltip. The tooltip explains; the label names. Both are here so they
/// cannot drift apart, and both are pure, so a control that ships announcing its icon is a
/// failing test rather than something only a VoiceOver user finds out about.
enum IslandControlCopy {
    /// One control, as the accessibility tree should see it.
    struct Control: Equatable {
        /// What it is. Never a symbol name, never a sentence.
        let label: String
        /// What state it is in, for controls that have one.
        let value: String?
        /// What it will do. Also the tooltip.
        let hint: String
    }

    static let on = "On"
    static let off = "Off"

    static func attach(isBusy: Bool) -> Control {
        Control(
            label: "Attach files",
            value: nil,
            hint: isBusy ? "Not available while Logue is answering" : "Attach files to this message"
        )
    }

    static func webSearch(isOn: Bool) -> Control {
        Control(
            label: "Web search",
            value: isOn ? on : off,
            hint: isOn ? "Web search is on for this message" : "Search the web for this message"
        )
    }

    static func deepResearch(isOn: Bool) -> Control {
        Control(
            label: "Deep Research",
            value: isOn ? on : off,
            hint: isOn
                ? "Deep Research is on for this message"
                : "Research this in depth before answering"
        )
    }

    static func microphone(isRecording: Bool) -> Control {
        Control(
            label: "Voice input",
            value: isRecording ? "Recording" : "Off",
            hint: isRecording ? "Stop voice input" : "Dictate this message"
        )
    }

    /// The send button, which is a stop button mid-run.
    ///
    /// Two different actions rather than one in two states, so they are named differently —
    /// a control that keeps the name "Send" while it cancels is how someone stops a run they
    /// meant to let finish.
    static func send(canSend: Bool, isGenerating: Bool) -> Control {
        guard !isGenerating else {
            return Control(label: "Stop", value: nil, hint: "Stop generating this response")
        }
        return Control(
            label: "Send",
            value: nil,
            hint: canSend ? "Send this message" : "Type a message first"
        )
    }

    static let openInLogue = Control(
        label: "Open in Logue",
        value: nil,
        hint: "Continue this conversation in the main window"
    )

    static let close = Control(
        label: "Close",
        value: nil,
        hint: "Put the island away"
    )

    static let newConversation = Control(
        label: "New conversation",
        value: nil,
        hint: "Start a new thread. The current one stays in Logue"
    )
}
