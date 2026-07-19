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
            onTyping: onTyping
        )
    }

    final class Coordinator {
        var onCopy: () -> Void
        var onCut: () -> Void
        var onDelete: () -> Void
        var onSelectAll: () -> Void
        var onEscape: () -> Void
        var onTyping: ((_ character: String) -> Void)?

        init(
            onCopy: @escaping () -> Void,
            onCut: @escaping () -> Void,
            onDelete: @escaping () -> Void,
            onSelectAll: @escaping () -> Void,
            onEscape: @escaping () -> Void,
            onTyping: ((_ character: String) -> Void)?
        ) {
            self.onCopy = onCopy
            self.onCut = onCut
            self.onDelete = onDelete
            self.onSelectAll = onSelectAll
            self.onEscape = onEscape
            self.onTyping = onTyping
        }
    }
}

/// NSView that captures keyboard events during multi-block selection.
final class KeyHandlerNSView: NSView {
    var coordinator: MultiBlockKeyHandler.Coordinator?

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
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode

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
