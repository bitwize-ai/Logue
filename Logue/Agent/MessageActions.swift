import AppKit
import UniformTypeIdentifiers

/// What you can do with an assistant's answer, wherever it was asked from.
///
/// One definition because the two surfaces had drifted into offering different things: the
/// main window could export a response as Markdown but not save it as a note, and the
/// Command Center island could save a note but not export. Neither gap was a decision — each
/// surface simply grew the action someone needed while they were looking at it.
///
/// Free of SwiftUI so both a view and a floating panel can call it, and so the behaviour is
/// stated once rather than reimplemented per surface. `#61`'s ground rule: anything added to
/// one surface is added to both, by being mounted rather than redrawn.
@MainActor
enum MessageActions {
    /// Puts `text` on the pasteboard.
    ///
    /// No toast. `.toastOverlay()` is mounted in exactly one place — the main window's chat
    /// view — so a toast raised from the Command Center island either showed nothing or
    /// painted its confirmation in the window *behind* the pill, describing something the
    /// user did somewhere else. Each surface confirms in its own way instead: the main window
    /// keeps its toast at the call site, the island ticks the row you pressed.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HapticFeedback.copy()
    }

    /// Writes the answer to a file the user picks.
    ///
    /// The panel is presented rather than a path invented: this is the user's filesystem, and
    /// a silent write to Documents is how a feature becomes a thing people cannot find again.
    static func exportMarkdown(_ text: String, suggestedName: String = "logue-response.md") {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown") ?? .plainText]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Surfaced rather than only logged: the user asked for a file and there is
                // now no file, which is not something to discover later.
                Task { @MainActor in
                    ToastCenter.shared.show("Could not export: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Keeps the answer as a document in the library.
    ///
    /// Returns the new document's id so a caller can show its own confirmation against the
    /// message it came from — the island marks the row it saved, which needs the pairing.
    @discardableResult
    static func saveAsNote(_ text: String, title: String = "Chat Note") -> UUID {
        let document = DocumentStore.shared.createDocument(title: title)
        var updated = document
        updated.body = text
        DocumentStore.shared.updateDocument(updated)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        return document.id
    }
}
