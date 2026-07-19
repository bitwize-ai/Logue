import SwiftUI
import Textual

/// Renders markdown content as rich text using Textual with GitHub-style tables,
/// syntax-highlighted code blocks, and proper heading/list rendering.
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        StructuredText(markdown: text)
            .font(.callout)
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(.gitHub)
            .textual.overflowMode(.scroll)
    }
}
