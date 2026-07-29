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

    /// The regression this rule exists for. SwiftUI echoes the split view's visibility back
    /// through the binding right after a menu item sets a mode, and the echo arrives while the
    /// binding still reads the previous mode. If a "list is visible" report were allowed to
    /// name a mode, that stale read is what it would name it from — which is how every ⌘3
    /// pressed from editor-only used to land on editor-and-list.
    @Test("A report that the list is visible never changes the mode")
    func visibleListReportIsIgnored() {
        #expect(EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: true) == nil)
    }

    /// Specifically: from every mode, including the one whose stale `showsInspector` caused the
    /// bug, a visible-list report must leave the stored mode alone.
    @Test("No mode is rewritten by a visible-list report", arguments: EditorLayoutMode.allCases)
    func visibleListReportPreservesEveryMode(mode: EditorLayoutMode) {
        let reported = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: true)
        #expect(reported == nil, "\(mode) would have been overwritten by a visible-list report")
    }

    /// The one direction that *is* inferred: the user dragging the sidebar shut is recorded, so
    /// a collapsed sidebar does not come back on the next launch.
    @Test("A collapse is recorded as editor-only")
    func collapseReportIsRecorded() {
        #expect(EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false) == .editorOnly)
    }

    /// Recording a collapse has to be idempotent, because the split view echoes our own
    /// `.detailOnly` straight back at us.
    @Test("Recording a collapse twice is stable")
    func collapseIsIdempotent() {
        let first = EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: false)
        #expect(first == .editorOnly)
        #expect(first?.showsList == false)
        #expect(EditorLayoutMode.modeAfterVisibilityReport(listIsVisible: first?.showsList ?? true) == .editorOnly)
    }
}
