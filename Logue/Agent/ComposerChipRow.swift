import Foundation

/// How many chips a composer shows before it starts counting the rest.
///
/// The island floated its chips in an overlay offset above the pill, which meant two things.
/// They took no layout space, so with a conversation on screen they drew over the bottom of
/// the transcript; and nothing bounded them, so attaching six files ran the row past the
/// island's width and off both ends.
///
/// The ordering rule is the part worth stating: **modes are never hidden.** A mode chip says
/// what the send is about to *do* — search the web, spend minutes on Deep Research — and a
/// hidden one is a send the user did not know they were making. An attachment chip only says
/// what is going with it, and "+3 more" loses nothing that matters, because the files are
/// still attached and still listed the moment one is removed.
///
/// Free of SwiftUI so the arithmetic is testable without a bar to put it in.
enum ComposerChipRow {
    /// What to draw.
    struct Layout: Equatable {
        /// Mode chips to render. Always every one of them.
        let modes: Int
        /// Attachment chips to render, oldest first.
        let attachments: Int
        /// Attachments not rendered, summarised by a single counter chip.
        let hidden: Int

        var showsOverflow: Bool {
            hidden > 0
        }
    }

    /// Chips the island's single row can hold before it looks like a list.
    static let islandLimit = 4

    static func layout(modeCount: Int, attachmentCount: Int, limit: Int = islandLimit) -> Layout {
        let modes = max(0, modeCount)
        let attachments = max(0, attachmentCount)

        // Modes first, and they are not subject to the limit — see the note above. A limit
        // smaller than the number of modes is a layout that cannot be honoured, and dropping
        // a mode is the wrong way to honour it.
        let remaining = max(0, limit - modes)
        guard attachments > remaining else {
            return Layout(modes: modes, attachments: attachments, hidden: 0)
        }

        // One of the remaining slots goes to the counter itself, so the row does not grow by
        // adding the thing that says the row is full.
        let shown = max(0, remaining - 1)
        return Layout(modes: modes, attachments: shown, hidden: attachments - shown)
    }
}
