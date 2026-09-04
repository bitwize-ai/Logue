import Testing
@testable import Logue

/// What a string picked up somewhere else may look like once it is shown.
///
/// The approval card is the reason these are not merely cosmetic: it names the thing a
/// destructive tool is about to act on, directly above a Touch ID prompt, and the name it
/// shows can come from a `.md` file dropped into the markdown folder or from a call a
/// prompt-injected model made.
@Suite("Display text")
struct DisplayTextTests {
    // MARK: - The part that is a security control

    @Test("A bidirectional override cannot survive into a label")
    func stripsBidiOverride() {
        // U+202E reverses the display of everything after it. Left in a document title it
        // lets `Delete “report.txt”` render as a different filename on the one card whose
        // job is to be true.
        let spoofed = "report\u{202E}gnp.txt"
        let shown = DisplayText.singleLine(spoofed)
        #expect(shown.unicodeScalars.contains { $0.value == 0x202E } == false)
        #expect(shown == "reportgnp.txt")
    }

    @Test("Every bidirectional control is stripped, not only the one we thought of")
    func stripsEveryBidiControl() {
        // Pinning the *set*, not one example: `CharacterSet.controlCharacters` is Unicode
        // categories Cc and Cf, and this is what makes that claim testable rather than
        // merely plausible. LRO, RLO, LRE, RLE, PDF, LRI, RLI, FSI, PDI.
        for scalar in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069] {
            let unicode = Unicode.Scalar(scalar)
            #expect(unicode != nil)
            guard let unicode else { continue }
            let shown = DisplayText.singleLine("a\(String(Character(unicode)))b")
            #expect(
                shown.unicodeScalars.contains { $0.value == UInt32(scalar) } == false,
                "U+\(String(scalar, radix: 16, uppercase: true)) survived"
            )
        }
    }

    @Test("C0 control characters are stripped")
    func stripsC0Controls() {
        let shown = DisplayText.singleLine("a\u{0000}b\u{0007}c\u{001B}d")
        #expect(shown == "abcd")
    }

    @Test("A zero-width joiner cannot pad a name out of view")
    func stripsZeroWidth() {
        #expect(DisplayText.singleLine("a\u{200B}\u{200D}\u{FEFF}b").contains("\u{200B}") == false)
    }

    // MARK: - One line

    @Test("A multi-line value becomes one line")
    func collapsesNewlines() {
        // The newline becomes a space rather than disappearing. A newline is itself a
        // control character, so stripping controls before splitting produced `firstsecond`
        // — a different value, silently. That is the mistake this shape invites.
        #expect(DisplayText.singleLine("first\nsecond\n\nthird") == "first second third")
        #expect(DisplayText.singleLine("a\tb") == "a b")
        #expect(DisplayText.singleLine("a\r\nb") == "a b")
    }

    @Test("Runs of whitespace collapse to a single space")
    func collapsesRuns() {
        #expect(DisplayText.singleLine("  a \t\t b  ") == "a b")
    }

    @Test("Ordinary text is left exactly as it is")
    func leavesTextAlone() {
        #expect(DisplayText.singleLine("Q3 Planning — notes (v2)") == "Q3 Planning — notes (v2)")
    }

    @Test("Text that is only control characters comes back empty, not mangled")
    func allControls() {
        #expect(DisplayText.singleLine("\u{202E}\u{0007}").isEmpty)
    }

    // MARK: - Clamping

    @Test("The ellipsis is inside the budget, never added to it")
    func clampNeverExceedsItsLimit() {
        for limit in 0 ... 40 {
            let clamped = DisplayText.clamp(String(repeating: "x", count: 100), to: limit)
            #expect(clamped.count <= limit, "limit \(limit) produced \(clamped.count)")
        }
    }

    @Test("A value inside the limit is returned untouched")
    func shortValueUnchanged() {
        #expect(DisplayText.clamp("short", to: 10) == "short")
    }

    @Test("A cut value says it was cut")
    func cutValueIsMarked() {
        #expect(DisplayText.clamp("abcdefghij", to: 5) == "abcd…")
    }
}
