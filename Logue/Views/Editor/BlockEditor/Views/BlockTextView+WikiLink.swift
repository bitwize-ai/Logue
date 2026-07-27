import AppKit

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

extension BlockNSTextView {
    /// Offers link completions when the caret sits inside an unclosed `[[`.
    ///
    /// Called after text changes. Does nothing when there is no in-progress link, so
    /// it is safe to call on every keystroke.
    func presentWikiLinkCompletionIfNeeded() {
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

        menu.popUp(positioning: nil, at: caretPointForMenu(), in: self)
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
