import AppKit
import SwiftUI

/// An invisible NSViewRepresentable that becomes first responder during multi-block selection.
/// Intercepts keyboard shortcuts (Cmd+C, Cmd+X, Cmd+A, Delete, Escape) and forwards them
/// to the block editor's multi-block selection handlers.
struct MultiBlockKeyHandler: NSViewRepresentable {
    var onCopy: () -> Void
    var onCut: () -> Void
    var onDelete: () -> Void
    var onSelectAll: () -> Void
    var onEscape: () -> Void
    /// Called when user types a character — clears selection and starts typing.
    var onTyping: ((_ character: String) -> Void)?
    /// Cmd+V — replace the selected blocks with the clipboard contents.
    var onPaste: (() -> Void)?
    /// Cmd+Shift+Up — move the selected blocks up one position.
    var onMoveUp: (() -> Void)?
    /// Cmd+Shift+Down — move the selected blocks down one position.
    var onMoveDown: (() -> Void)?

    func makeNSView(context: Context) -> KeyHandlerNSView {
        let view = KeyHandlerNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyHandlerNSView, context: Context) {
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCopy: onCopy,
            onCut: onCut,
            onDelete: onDelete,
            onSelectAll: onSelectAll,
            onEscape: onEscape,
            onTyping: onTyping,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onPaste: onPaste
        )
    }

    final class Coordinator {
        var onCopy: () -> Void
        var onCut: () -> Void
        var onDelete: () -> Void
        var onSelectAll: () -> Void
        var onEscape: () -> Void
        var onTyping: ((_ character: String) -> Void)?
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onPaste: (() -> Void)?

        init(
            onCopy: @escaping () -> Void,
            onCut: @escaping () -> Void,
            onDelete: @escaping () -> Void,
            onSelectAll: @escaping () -> Void,
            onEscape: @escaping () -> Void,
            onTyping: ((_ character: String) -> Void)?,
            onMoveUp: (() -> Void)?,
            onMoveDown: (() -> Void)?,
            onPaste: (() -> Void)?
        ) {
            self.onCopy = onCopy
            self.onCut = onCut
            self.onDelete = onDelete
            self.onSelectAll = onSelectAll
            self.onEscape = onEscape
            self.onTyping = onTyping
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onPaste = onPaste
        }
    }
}

/// NSView that captures keyboard events during multi-block selection.
final class KeyHandlerNSView: NSView {
    var coordinator: MultiBlockKeyHandler.Coordinator?

    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125

    override var acceptsFirstResponder: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "c":
            coordinator?.onCopy()
            return true
        case "x":
            coordinator?.onCut()
            return true
        case "a":
            coordinator?.onSelectAll()
            return true
        case "v":
            // `onPaste` is optional-chained — unlike `onCut`/`onSelectAll` — so nil is reachable.
            // Returning true there swallowed Cmd+V instead of letting the responder chain paste,
            // and the same key path matched Cmd+Option+V.
            guard !event.modifierFlags.contains(.option), let onPaste = coordinator?.onPaste else {
                return super.performKeyEquivalent(with: event)
            }
            onPaste()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Shift+Up/Down (126/125) — reorder the selection. Checked before the
        // fall-through below, which clears the selection on any other arrow key.
        if flags.contains(.command), flags.contains(.shift) {
            if keyCode == Self.upArrowKeyCode {
                coordinator?.onMoveUp?()
                return
            }
            if keyCode == Self.downArrowKeyCode {
                coordinator?.onMoveDown?()
                return
            }
        }

        // Escape (53)
        if keyCode == 53 {
            coordinator?.onEscape()
            return
        }

        // Delete (51) or Forward Delete (117)
        if keyCode == 51 || keyCode == 117 {
            coordinator?.onDelete()
            return
        }

        // Any printable character — clear selection and forward to editor
        if let chars = event.characters, !chars.isEmpty,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control)
        {
            coordinator?.onTyping?(chars)
            return
        }

        // Arrow keys or other non-printable — clear selection
        coordinator?.onEscape()
    }
}
