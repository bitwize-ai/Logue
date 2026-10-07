import Foundation
import Testing

@testable import Logue

/// What the island's controls announce.
///
/// Almost every one carried only `.help(…)`, which on macOS is the accessibility hint rather
/// than the label — so VoiceOver fell back to the SF Symbol name. The send button announced
/// "arrow up".
@Suite("IslandControlCopy")
struct IslandControlCopyTests {
    /// Every control, in every state it has.
    private var allControls: [IslandControlCopy.Control] {
        [
            IslandControlCopy.microphone(isRecording: false),
            IslandControlCopy.microphone(isRecording: true),
            IslandControlCopy.send(canSend: false, isGenerating: false, isBusy: false),
            IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: false),
            IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: true),
            IslandControlCopy.send(canSend: false, isGenerating: true, isBusy: false),
            IslandControlCopy.openInLogue,
            IslandControlCopy.close,
            IslandControlCopy.newConversation,
        ]
    }

    @Test("Nothing announces its icon")
    func noControlAnnouncesASymbolName() {
        // The regression this exists to catch. An SF Symbol name is dotted and lowercase —
        // "arrow.up", "sparkle.magnifyingglass", "xmark.circle.fill" — and reaches VoiceOver
        // whenever a Button's only content is an Image with no label of its own.
        for control in allControls {
            #expect(control.label.contains(".") == false, "symbol-shaped label: \(control.label)")
            #expect(control.label.isEmpty == false)
            #expect(control.label.first?.isUppercase == true, "not a name: \(control.label)")
        }
    }

    @Test("Every control says what it will do")
    func everyControlHasAHint() {
        for control in allControls {
            #expect(control.hint.isEmpty == false, "no hint for \(control.label)")
        }
    }

    // MARK: - State

    @Test("The two states of a toggle are told apart")
    func toggleStatesDiffer() {
        for pair in [
            (IslandControlCopy.microphone(isRecording: true), IslandControlCopy.microphone(isRecording: false)),
        ] {
            #expect(pair.0 != pair.1)
            #expect(pair.0.label == pair.1.label, "the name does not change with the state")
        }
    }

    @Test("Stop is not called Send")
    func stopIsNamedForWhatItDoes() {
        // A control that keeps the name "Send" while it cancels is how someone stops a run
        // they meant to let finish.
        let sending = IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: false)
        let stopping = IslandControlCopy.send(canSend: false, isGenerating: true, isBusy: false)
        #expect(sending.label == "Send")
        #expect(stopping.label == "Stop")
    }

    @Test("A send that cannot fire says why")
    func disabledSendExplainsItself() {
        let idle = IslandControlCopy.send(canSend: false, isGenerating: false, isBusy: false)
        let ready = IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: false)
        #expect(idle.hint != ready.hint)
    }

    @Test("A send blocked by other work does not claim it will send")
    func busySendExplainsItself() {
        // The button is disabled while the engine runs something else. Its hint used to
        // read "Send this message" regardless — the tooltip contradicting the control.
        let ready = IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: false)
        let busy = IslandControlCopy.send(canSend: true, isGenerating: false, isBusy: true)
        #expect(busy.hint != ready.hint)
        #expect(busy.label == "Send")
        // Nothing typed is the nearer reason, and the one the user can do something about.
        let empty = IslandControlCopy.send(canSend: false, isGenerating: false, isBusy: true)
        #expect(empty.hint == IslandControlCopy.send(canSend: false, isGenerating: false, isBusy: false).hint)
    }
}
