import Foundation

/// A single Canvas version. Each time the agent emits a long code block /
/// HTML / mermaid response, we capture it as a snapshot so the user can
/// flip between iterations.
struct CanvasSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    /// Display label for the version selector ("v1", "v2"). Auto-numbered.
    var label: String
    /// Source language tag (`swift`, `html`, `mermaid`, etc.). Drives the
    /// preview path.
    var language: String
    /// Raw content. For `mermaid` this is the diagram source; for `html`
    /// the doc; for `swift` / others the code.
    var content: String
    /// When this snapshot was generated.
    let createdAt: Date

    init(
        id: UUID = .init(),
        label: String,
        language: String,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.language = language
        self.content = content
        self.createdAt = createdAt
    }
}

extension CanvasSnapshot {
    /// True for languages that warrant a live preview pane.
    var supportsPreview: Bool {
        switch language.lowercased() {
        case "html", "svg", "mermaid", "slidedeck": true
        default: false
        }
    }

    /// True when this snapshot was emitted by the slide deck generator
    /// and should expose the Export PDF affordance.
    var isSlideDeck: Bool {
        language.lowercased() == "slidedeck"
    }
}
