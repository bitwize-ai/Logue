import Foundation
@testable import Logue
import Testing

/// Rewriting inbound links when a title changes, so a rename does not silently
/// break every reference to it.
@Suite("LinkRename")
struct LinkRenameTests {
    // MARK: - Body rewriting

    @Test("A bare link is retargeted")
    func rewritesBareLink() {
        let result = LinkRenamer.rewriting(body: "see [[Alpha]] now", from: "Alpha", to: "Beta")
        #expect(result == "see [[Beta]] now")
    }

    @Test("Every occurrence is retargeted")
    func rewritesAllOccurrences() {
        let result = LinkRenamer.rewriting(body: "[[Alpha]] and [[Alpha]]", from: "Alpha", to: "Beta")
        #expect(result == "[[Beta]] and [[Beta]]")
    }

    @Test("Matching is case-insensitive, and the new title's casing wins")
    func caseInsensitiveMatch() {
        let result = LinkRenamer.rewriting(body: "[[alpha]]", from: "Alpha", to: "Beta")
        #expect(result == "[[Beta]]")
    }

    @Test("An aliased link keeps its display text")
    func preservesAlias() {
        let result = LinkRenamer.rewriting(
            body: "[[Alpha|the first one]]", from: "Alpha", to: "Beta"
        )
        #expect(result == "[[Beta|the first one]]")
    }

    @Test("Links to other titles are untouched")
    func leavesOtherLinksAlone() {
        let result = LinkRenamer.rewriting(body: "[[Alpha]] [[Gamma]]", from: "Alpha", to: "Beta")
        #expect(result == "[[Beta]] [[Gamma]]")
    }

    @Test("Plain prose mentioning the title is untouched")
    func leavesProseAlone() {
        let result = LinkRenamer.rewriting(body: "Alpha is great", from: "Alpha", to: "Beta")
        #expect(result == "Alpha is great")
    }

    @Test("A body with no links is returned unchanged")
    func noLinks() {
        #expect(LinkRenamer.rewriting(body: "nothing", from: "Alpha", to: "Beta") == "nothing")
    }

    @Test("Renaming to the same title changes nothing")
    func sameTitleIsNoOp() {
        #expect(LinkRenamer.rewriting(body: "[[Alpha]]", from: "Alpha", to: "Alpha") == "[[Alpha]]")
    }

    @Test("An empty new title is refused so links are not corrupted")
    func emptyNewTitleRefused() {
        #expect(LinkRenamer.rewriting(body: "[[Alpha]]", from: "Alpha", to: "  ") == "[[Alpha]]")
    }

    @Test("A new title containing link syntax is sanitised")
    func sanitisesNewTitle() {
        let result = LinkRenamer.rewriting(body: "[[Alpha]]", from: "Alpha", to: "Be|ta]]")
        #expect(result == "[[Beta]]")
    }

    @Test("Surrounding unicode is preserved exactly")
    func preservesUnicode() {
        let result = LinkRenamer.rewriting(
            body: "👩‍💻 記録 [[Alpha]] 終わり", from: "Alpha", to: "Beta"
        )
        #expect(result == "👩‍💻 記録 [[Beta]] 終わり")
    }

    @Test("Whitespace inside the link braces is tolerated")
    func tolerantOfInnerWhitespace() {
        #expect(LinkRenamer.rewriting(body: "[[ Alpha ]]", from: "Alpha", to: "Beta") == "[[Beta]]")
    }

    // MARK: - Relationship rewriting

    @Test("Relationship targets are retargeted")
    func rewritesRelationships() {
        var doc = WritingDocument()
        doc.setRelationship(.belongsTo, targets: ["Alpha", "Gamma"])

        let updated = LinkRenamer.rewriting(document: doc, from: "Alpha", to: "Beta")

        #expect(updated.typedRelationships[.belongsTo] == ["Beta", "Gamma"])
    }

    @Test("A document with nothing to change is reported as unchanged")
    func unchangedDocumentDetectable() {
        var doc = WritingDocument()
        doc.body = "no links here"

        #expect(LinkRenamer.needsRewrite(document: doc, from: "Alpha") == false)
    }

    @Test("A document with a matching link is reported as needing a rewrite")
    func changedDocumentDetectable() {
        var doc = WritingDocument()
        doc.body = "[[Alpha]]"

        #expect(LinkRenamer.needsRewrite(document: doc, from: "Alpha"))
    }

    @Test("A document whose only reference is a relationship needs a rewrite")
    func relationshipOnlyNeedsRewrite() {
        var doc = WritingDocument()
        doc.setRelationship(.relatedTo, targets: ["Alpha"])

        #expect(LinkRenamer.needsRewrite(document: doc, from: "Alpha"))
    }

    @Test("Rewriting a document updates both body and relationships")
    func rewritesBoth() {
        var doc = WritingDocument()
        doc.body = "see [[Alpha]]"
        doc.setRelationship(.has, targets: ["Alpha"])

        let updated = LinkRenamer.rewriting(document: doc, from: "Alpha", to: "Beta")

        #expect(updated.body == "see [[Beta]]")
        #expect(updated.typedRelationships[.has] == ["Beta"])
    }
}
