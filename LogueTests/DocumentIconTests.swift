import Foundation
@testable import Logue
import Testing

@Suite("DocumentIcon")
struct DocumentIconTests {
    @Test("Legacy JSON without an icon decodes without throwing")
    func legacyJSONDecodes() throws {
        let legacy = """
        {
            "id": "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40",
            "title": "Legacy", "body": "", "goalMode": "casual",
            "createdAt": 0, "modifiedAt": 0, "isFavorited": false,
            "tags": [], "chatMessages": [], "isTrashed": false
        }
        """
        let doc = try JSONDecoder().decode(WritingDocument.self, from: Data(legacy.utf8))
        #expect(doc.icon == nil)
    }

    @Test("Icon survives an encode/decode round trip")
    func roundTrip() throws {
        var doc = WritingDocument()
        doc.icon = "📄"
        let decoded = try JSONDecoder().decode(WritingDocument.self, from: JSONEncoder().encode(doc))
        #expect(decoded.icon == "📄")
    }

    @Test("A single emoji is accepted")
    func acceptsEmoji() {
        #expect(DocumentIcon.sanitised("📄") == "📄")
    }

    @Test("Control characters and newlines are rejected")
    func rejectsControlCharacters() {
        #expect(DocumentIcon.sanitised("a\nb") == nil)
        #expect(DocumentIcon.sanitised("\u{0}") == nil)
    }

    @Test("An over-long string is rejected rather than truncated mid-emoji")
    func rejectsOverLongInput() {
        #expect(DocumentIcon.sanitised("📄📄📄📄📄📄") == nil)
    }

    @Test("Empty or whitespace-only input clears the icon")
    func emptyClearsIcon() {
        #expect(DocumentIcon.sanitised("") == nil)
        #expect(DocumentIcon.sanitised("   ") == nil)
    }

    @Test("A multi-scalar emoji counts as one character")
    func multiScalarEmojiAccepted() {
        #expect(DocumentIcon.sanitised("👩‍💻") == "👩‍💻")
    }
}

@Suite("EditorLayoutMode")
struct EditorLayoutModeTests {
    @Test("Each shortcut number maps to a distinct layout")
    func shortcutMapping() {
        #expect(EditorLayoutMode(shortcutNumber: 1) == .editorOnly)
        #expect(EditorLayoutMode(shortcutNumber: 2) == .editorAndList)
        #expect(EditorLayoutMode(shortcutNumber: 3) == .allPanels)
    }

    @Test("An unknown shortcut number resolves to nil")
    func unknownShortcut() {
        #expect(EditorLayoutMode(shortcutNumber: 0) == nil)
        #expect(EditorLayoutMode(shortcutNumber: 9) == nil)
    }

    @Test("Only the all-panels layout shows the inspector")
    func inspectorVisibility() {
        #expect(EditorLayoutMode.editorOnly.showsInspector == false)
        #expect(EditorLayoutMode.editorAndList.showsInspector == false)
        #expect(EditorLayoutMode.allPanels.showsInspector)
    }

    @Test("Editor-only hides the list, the other layouts show it")
    func listVisibility() {
        #expect(EditorLayoutMode.editorOnly.showsList == false)
        #expect(EditorLayoutMode.editorAndList.showsList)
        #expect(EditorLayoutMode.allPanels.showsList)
    }

    @Test("Every layout has a menu label")
    func allHaveLabels() {
        for mode in EditorLayoutMode.allCases {
            #expect(!mode.label.isEmpty)
        }
    }

    @Test("Layout persists as a stable raw value")
    func stableRawValues() {
        #expect(EditorLayoutMode(rawValue: "allPanels") == .allPanels)
    }

    /// The View menu builds its ⌘1 / ⌘2 / ⌘3 items from `1 ... allCases.count` and resolves
    /// each through `init(shortcutNumber:)`, so a case added without a number would silently
    /// go unbound rather than fail to compile.
    @Test("Every layout is reachable from a shortcut number")
    func everyLayoutHasAShortcut() {
        let reachable = (1 ... EditorLayoutMode.allCases.count)
            .compactMap { EditorLayoutMode(shortcutNumber: $0) }
        #expect(Set(reachable) == Set(EditorLayoutMode.allCases))
    }

    /// A value written by a future version, or a corrupted one, must not leave the window in
    /// a state no shortcut can describe — callers fall back to `allPanels`.
    @Test("An unrecognised stored value is not a layout")
    func unknownRawValue() {
        #expect(EditorLayoutMode(rawValue: "splitScreenTriptych") == nil)
    }

    /// The regression the echo test exists for. SwiftUI echoes the split view's visibility back
    /// through the binding right after a menu item sets a mode. A report that agrees with the
    /// stored mode is that echo, and acting on it is how every ⌘3 pressed from editor-only used
    /// to land on editor-and-list.
    @Test("An echo of the stored mode changes nothing", arguments: EditorLayoutMode.allCases)
    func echoOfStoredModeChangesNothing(mode: EditorLayoutMode) {
        let echo = EditorLayoutMode.modeAfterVisibilityReport(
            listIsVisible: mode.showsList, current: mode
        )
        #expect(echo == nil, "\(mode) would have been overwritten by an echo of itself")
    }

    /// The bug that made the rule symmetric: the window's sidebar toggle reports the list as
    /// visible, and while visible-list reports were dropped the button did nothing at all.
    @Test("Showing the list from editor-only is honoured")
    func showingTheListIsHonoured() {
        let next = EditorLayoutMode.modeAfterVisibilityReport(
            listIsVisible: true, current: .editorOnly
        )
        #expect(next == .editorAndList)
        #expect(next?.showsList == true)
    }

    /// The user dragging the sidebar shut is recorded, so a collapsed sidebar does not come
    /// back on the next launch.
    @Test("A collapse hides the list", arguments: [EditorLayoutMode.allPanels, .editorAndList])
    func collapseReportHidesTheList(from mode: EditorLayoutMode) {
        let next = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false, current: mode)
        #expect(next?.showsList == false)
    }

    /// The bug this case was added for. Closing the navigation sidebar used to land on
    /// `editorOnly`, which took the tools sidebar down with it — one drag, two panes gone.
    @Test("Collapsing the list leaves the inspector alone", arguments: EditorLayoutMode.allCases)
    func collapsePreservesTheInspector(from mode: EditorLayoutMode) {
        guard let next = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false, current: mode)
        else { return } // Already listless — an echo, nothing to check.
        #expect(next.showsInspector == mode.showsInspector, "\(mode) lost its inspector to a list collapse")
    }

    @Test("Showing the list leaves the inspector alone", arguments: EditorLayoutMode.allCases)
    func showPreservesTheInspector(from mode: EditorLayoutMode) {
        guard let next = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: true, current: mode)
        else { return }
        #expect(next.showsInspector == mode.showsInspector, "\(mode) gained or lost an inspector")
    }

    /// Hiding and showing has to return where it started, or the toolbar button is not a toggle.
    /// This is the round trip that was one-way: the sidebar went and could not be brought back.
    @Test("Hiding then showing the list returns to the same mode", arguments: EditorLayoutMode.allCases)
    func hideThenShowRoundTrips(from mode: EditorLayoutMode) {
        let hidden = mode.withoutList
        #expect(hidden.showsList == false)
        #expect(hidden.withList == mode.withList)
        #expect(hidden.withList.showsInspector == mode.showsInspector)
    }

    /// Every combination of the two panes has a mode, which is the whole reason there are four.
    @Test("Every list/inspector combination is representable")
    func everyPaneCombinationExists() {
        let combinations = Set(EditorLayoutMode.allCases.map { [$0.showsList, $0.showsInspector] })
        #expect(combinations.count == 4)
    }

    /// Recording a collapse has to be idempotent, because the split view echoes our own
    /// `.detailOnly` straight back at us.
    @Test("Recording a collapse twice is stable")
    func collapseIsIdempotent() {
        let first = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false, current: .allPanels)
        #expect(first == .editorAndInspector)

        // The echo of that write, read with the mode it just stored.
        let echo = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false, current: .editorAndInspector)
        #expect(echo == nil)
    }
}
