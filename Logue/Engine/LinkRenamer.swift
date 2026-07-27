import Foundation

/// Retargets `[[wikilinks]]` and relationship fields when a title changes.
///
/// Renaming a document otherwise breaks every inbound reference silently, which is
/// the worst failure mode for a link graph — nothing errors, the links just stop
/// resolving.
///
/// Rewrites only *link* references. Prose that happens to mention the old title is
/// left alone: the user wrote that sentence deliberately, and editing their prose
/// on a rename would be a surprise.
enum LinkRenamer {
    /// Rewrites every link in `body` that targets `oldTitle`.
    ///
    /// Preserves alias display text, so `[[Alpha|the first one]]` becomes
    /// `[[Beta|the first one]]`. Returns `body` unchanged when the new title is
    /// blank after sanitising, rather than writing a corrupt link.
    static func rewriting(body: String, from oldTitle: String, to newTitle: String) -> String {
        let replacement = sanitisedTitle(newTitle)
        guard !replacement.isEmpty else { return body }

        let oldKey = normalise(oldTitle)
        guard !oldKey.isEmpty else { return body }

        let nsBody = body as NSString
        var result = body

        // Rewrite back-to-front so earlier ranges stay valid as lengths change.
        for link in WikiLinkParser.links(in: body).reversed() {
            guard normalise(link.target) == oldKey else { continue }

            let rebuilt = if let display = link.displayText {
                "[[\(replacement)|\(display)]]"
            } else {
                "[[\(replacement)]]"
            }

            result = (result as NSString).replacingCharacters(in: link.range, with: rebuilt)
        }

        // Guard against a caller passing a body that no longer matches the ranges.
        return nsBody.length == (body as NSString).length ? result : body
    }

    /// Rewrites a document's body and relationship targets.
    static func rewriting(
        document: WritingDocument,
        from oldTitle: String,
        to newTitle: String
    ) -> WritingDocument {
        let replacement = sanitisedTitle(newTitle)
        guard !replacement.isEmpty else { return document }

        var updated = document
        updated.body = rewriting(body: document.body, from: oldTitle, to: newTitle)

        let oldKey = normalise(oldTitle)
        for (kind, targets) in document.typedRelationships {
            let rewritten = targets.map { target -> String in
                normalise(stripLinkSyntax(target)) == oldKey ? replacement : target
            }
            if rewritten != targets {
                updated.setRelationship(kind, targets: rewritten)
            }
        }

        return updated
    }

    /// Whether `document` references `oldTitle` at all — lets a caller skip
    /// rewriting and re-saving documents that would not change.
    static func needsRewrite(document: WritingDocument, from oldTitle: String) -> Bool {
        let oldKey = normalise(oldTitle)
        guard !oldKey.isEmpty else { return false }

        if WikiLinkParser.links(in: document.body).contains(where: { normalise($0.target) == oldKey }) {
            return true
        }
        return document.typedRelationships.values.contains { targets in
            targets.contains { normalise(stripLinkSyntax($0)) == oldKey }
        }
    }

    // MARK: - Private

    /// Strips the characters that carry meaning in link syntax, so a new title
    /// containing `|` or brackets cannot forge an alias or an unparseable link.
    private static func sanitisedTitle(_ title: String) -> String {
        var cleaned = title
        for token in ["[", "]", "|"] {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLinkSyntax(_ raw: String) -> String {
        WikiLinkParser.links(in: raw).first?.target ?? raw
    }

    private static func normalise(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
