import Foundation
import Testing

@testable import Logue

/// How many chips a composer shows before it starts counting the rest.
@Suite("ComposerChipRow")
struct ComposerChipRowTests {
    private func layout(modes: Int, attachments: Int, limit: Int = ComposerChipRow.islandLimit) -> ComposerChipRow.Layout {
        ComposerChipRow.layout(modeCount: modes, attachmentCount: attachments, limit: limit)
    }

    @Test("A row that fits shows everything")
    func everythingFits() {
        let result = layout(modes: 1, attachments: 2)
        #expect(result == ComposerChipRow.Layout(modes: 1, attachments: 2, hidden: 0))
        #expect(result.showsOverflow == false)
    }

    @Test("Exactly filling the row still hides nothing")
    func exactFitHidesNothing() {
        // The boundary that invites an off-by-one: at the limit there is nothing to count, so
        // spending a slot on a counter reading "+0 more" would be worse than not having one.
        let result = layout(modes: 0, attachments: 4)
        #expect(result.attachments == 4)
        #expect(result.hidden == 0)
    }

    @Test("Overflow is counted, and the counter pays for its own slot")
    func overflowTakesASlot() {
        // Four slots, six files: three chips and "+3 more" — not four chips and "+2 more",
        // which would be five things in a four-slot row.
        let result = layout(modes: 0, attachments: 6)
        #expect(result.attachments == 3)
        #expect(result.hidden == 3)
        #expect(result.attachments + 1 <= ComposerChipRow.islandLimit)
    }

    @Test("Nothing is ever lost")
    func everyAttachmentIsAccountedFor() {
        for attachments in 0 ... 40 {
            for modes in 0 ... 2 {
                let result = layout(modes: modes, attachments: attachments)
                #expect(result.attachments + result.hidden == attachments)
                #expect(result.modes == modes)
            }
        }
    }

    // MARK: - Modes are never hidden

    @Test("Modes survive a row too small to hold them")
    func modesAreNeverDropped() {
        // A mode chip says what the send is about to *do*. A hidden Deep Research chip is a
        // send the user did not know they were making — so a limit that cannot be honoured is
        // exceeded rather than met by dropping one.
        let result = layout(modes: 2, attachments: 0, limit: 1)
        #expect(result.modes == 2)
    }

    @Test("Modes take their slots before attachments do")
    func modesComeFirst() {
        let withoutModes = layout(modes: 0, attachments: 5)
        let withModes = layout(modes: 2, attachments: 5)
        #expect(withModes.attachments < withoutModes.attachments)
        #expect(withModes.hidden > withoutModes.hidden)
    }

    @Test("A row that is all modes hides every attachment behind a counter")
    func modesCanConsumeTheRow() {
        let result = layout(modes: 4, attachments: 3)
        #expect(result.modes == 4)
        #expect(result.attachments == 0)
        #expect(result.hidden == 3, "still counted, never silently dropped")
    }

    // MARK: - Degenerate inputs

    @Test("Nothing in, nothing out")
    func emptyIsEmpty() {
        #expect(layout(modes: 0, attachments: 0) == ComposerChipRow.Layout(modes: 0, attachments: 0, hidden: 0))
    }

    @Test("Negative counts cannot produce negative chips")
    func negativesAreClamped() {
        let result = layout(modes: -3, attachments: -7)
        #expect(result.modes == 0)
        #expect(result.attachments == 0)
        #expect(result.hidden == 0)
    }
}
