import AppKit
import OSLog

// MARK: - WikiLink Completion Menu

/// Menu target for the `[[` completion menu.
///
/// A separate `NSObject` because `NSMenuItem` needs an ObjC target, mirroring
/// `SlashMenuTarget`. Held by the text view so it outlives menu presentation.
final class WikiLinkMenuTarget: NSObject {
    private let handler: (WikiLinkCandidate) -> Void
    private let candidatesByID: [UUID: WikiLinkCandidate]

    init(candidates: [WikiLinkCandidate], handler: @escaping (WikiLinkCandidate) -> Void) {
        self.handler = handler
        candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    }

    @objc
    func menuAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let candidate = candidatesByID[id]
        else { return }
        handler(candidate)
    }
}

/// On `MarkdownNSTextView`, not `BlockNSTextView`, so table cells get it too.
///
/// The styler runs in table cells — `TableCellNSTextView` also inherits `MarkdownNSTextView` — so a
/// wikilink inside a table was underlined, coloured, and carried a `logue-wikilink://` URL, but the
/// handler that intercepts it was one subclass over. Clicking one handed the URL to macOS, which
/// answered "there is no application set to open the URL". Registering the scheme would be the wrong
/// fix: nothing outside the app should be able to open these.
extension MarkdownNSTextView {
    /// AppKit's link-click entry point.
    ///
    /// Reached for a plain click when the view is not editable and for Command-click
    /// when it is — exactly the behaviour we want, and all of it handled by AppKit
    /// rather than by intercepting `mouseDown`.
    override func clicked(onLink link: Any, at charIndex: Int) {
        let url: URL? = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))

        if let url, let target = WikiLinkURL.target(from: url) {
            if !ContentNavigator.openWikiLink(target: target) {
                Self.wikiLinkLogger.info("Clicked an unresolved wikilink target")
            }
            return
        }

        super.clicked(onLink: link, at: charIndex)
    }

    /// Follows a `[[wikilink]]` under the pointer when Command is held.
    ///
    /// Command-click rather than plain click: this is an editable body, so a plain
    /// click must keep placing the caret. Returns whether a link was followed, so
    /// the caller can fall back to normal click handling.
    func followWikiLinkIfCommandClicked(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        else { return false }

        let point = convert(event.locationInWindow, from: nil)
        guard let target = wikiLinkTarget(at: point) else { return false }

        if !ContentNavigator.openWikiLink(target: target) {
            Self.wikiLinkLogger.info("Command-clicked an unresolved wikilink target")
        }
        return true
    }

    /// The wikilink target under `point`, in this view's coordinates.
    ///
    /// Uses the glyph actually hit rather than the nearest insertion point:
    /// `characterIndexForInsertion` rounds to the closest boundary, so clicking the
    /// right-hand half of a link's last character resolves to the following
    /// character — the hidden `]]` — and finds no target.
    func wikiLinkTarget(at point: NSPoint) -> String? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }

        let length = (string as NSString).length
        guard length > 0 else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction
        )
        let index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard index >= 0, index < length else { return nil }

        return textStorage.attribute(
            MarkdownStyler.wikiLinkTargetAttribute, at: index, effectiveRange: nil
        ) as? String
    }

    private static let wikiLinkLogger = Logger(
        subsystem: AppConstants.bundleID, category: "WikiLinkClick"
    )

    /// Offers link completions when the caret sits inside an unclosed `[[`.
    ///
    /// Called after text changes. Does nothing when there is no in-progress link, so
    /// it is safe to call on every keystroke.
    func presentWikiLinkCompletionIfNeeded() {
        // Code blocks are this same class with styling off, so without this the menu opened while
        // typing a shell guard (`if [[ -z "$x" ]]`) or a Python slice, and the following keystrokes
        // went to the menu's type-select instead of into the code.
        guard markdownStyleEnabled else { return }

        guard let completion = WikiLinkCompletion.atCursor(
            in: string,
            cursor: selectedRange().location
        )
        else { return }

        let candidates = WikiLinkCandidates.matching(
            query: completion.query,
            documents: DocumentStore.shared.documents,
            meetings: MeetingStore.shared.meetings,
            excluding: DocumentStore.shared.selectedDocumentID
        )
        guard !candidates.isEmpty else { return }

        let target = WikiLinkMenuTarget(candidates: candidates) { [weak self] candidate in
            self?.insertWikiLink(title: candidate.title, over: completion.replacementRange)
        }
        wikiLinkMenuTarget = target

        let menu = NSMenu(title: "Link to")
        for candidate in candidates {
            let item = NSMenuItem(
                title: candidate.title,
                action: #selector(WikiLinkMenuTarget.menuAction(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(
                systemSymbolName: candidate.kind == .meeting ? "waveform" : "doc.text",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            item.representedObject = candidate.id
            item.target = target
            menu.addItem(item)
        }

        // Deferred one run-loop turn: this is reached from `insertText(_:replacementRange:)` while
        // `NSTextInputContext` is mid-`handleEvent`, and `NSMenu.popUp` spins a nested modal run
        // loop. Presenting from inside that is asking for input-system reentrancy.
        let point = caretPointForMenu()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            menu.popUp(positioning: nil, at: point, in: self)
        }
    }

    /// Replaces the in-progress `[[query` with a finished link.
    private func insertWikiLink(title: String, over range: NSRange) {
        let insertion = WikiLinkCompletion.insertionText(for: title)

        // The text may have changed between presenting the menu and choosing an
        // item, so re-validate the range instead of trusting it.
        let length = (string as NSString).length
        guard range.location >= 0, NSMaxRange(range) <= length else { return }
        guard shouldChangeText(in: range, replacementString: insertion) else { return }

        replaceCharacters(in: range, with: insertion)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (insertion as NSString).length, length: 0))
    }

    /// A point just below the caret, in this view's coordinates.
    private func caretPointForMenu() -> NSPoint {
        let caret = NSRange(location: selectedRange().location, length: 0)
        guard let layoutManager, let textContainer else { return .zero }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: caret, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += rect.height + textContainerInset.height + 4
        return rect.origin
    }
}
