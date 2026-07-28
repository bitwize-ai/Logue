import Foundation
@testable import Logue
import Testing

@Suite("LinkIndex")
struct LinkIndexTests {
    private let alphaID = UUID()
    private let betaID = UUID()
    private let gammaID = UUID()

    private func entry(_ id: UUID, _ title: String, _ body: String) -> LinkIndex.Entry {
        LinkIndex.Entry(id: id, title: title, body: body, kind: .document)
    }

    // MARK: - Outgoing

    @Test("Outgoing links resolve a target title to its item")
    func resolvesOutgoingLink() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "links to [[Beta]]"),
            entry(betaID, "Beta", ""),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
    }

    @Test("Title matching is case-insensitive")
    func caseInsensitiveResolution() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "see [[beta]]"),
            entry(betaID, "Beta", ""),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
    }

    @Test("A link to a title that does not exist resolves to nothing")
    func unresolvedLink() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha", "see [[Nowhere]]")])
        #expect(index.outgoing(from: alphaID).isEmpty)
    }

    @Test("Unresolved targets are reported so broken links can be surfaced")
    func brokenLinksReported() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha", "[[Nowhere]] and [[Missing]]")])
        #expect(Set(index.brokenTargets(from: alphaID)) == ["Nowhere", "Missing"])
    }

    @Test("A self-link is not reported as an outgoing link")
    func selfLinkExcluded() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha", "see [[Alpha]]")])
        #expect(index.outgoing(from: alphaID).isEmpty)
    }

    @Test("Duplicate links to the same target are reported once")
    func duplicateLinksDeduplicated() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "[[Beta]] and again [[Beta]]"),
            entry(betaID, "Beta", ""),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
    }

    // MARK: - Backlinks

    @Test("Backlinks list every item linking to a target")
    func backlinks() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "[[Gamma]]"),
            entry(betaID, "Beta", "[[Gamma]]"),
            entry(gammaID, "Gamma", ""),
        ])
        #expect(Set(index.backlinks(to: gammaID)) == [alphaID, betaID])
    }

    @Test("An item nobody links to has no backlinks")
    func noBacklinks() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha", "")])
        #expect(index.backlinks(to: alphaID).isEmpty)
    }

    @Test("Backlinks are the inverse of outgoing links")
    func backlinksAreInverseOfOutgoing() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "[[Beta]]"),
            entry(betaID, "Beta", ""),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
        #expect(index.backlinks(to: betaID) == [alphaID])
    }

    // MARK: - Mixed kinds

    @Test("Documents and meetings resolve against each other")
    func crossKindLinks() {
        let index = LinkIndex(entries: [
            LinkIndex.Entry(id: alphaID, title: "Standup", body: "notes in [[Spec]]", kind: .meeting),
            LinkIndex.Entry(id: betaID, title: "Spec", body: "", kind: .document),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
        #expect(index.backlinks(to: betaID) == [alphaID])
    }

    @Test("The kind of an indexed item is retrievable")
    func kindLookup() {
        let index = LinkIndex(entries: [
            LinkIndex.Entry(id: alphaID, title: "Standup", body: "", kind: .meeting),
        ])
        #expect(index.kind(of: alphaID) == .meeting)
        #expect(index.kind(of: betaID) == nil)
    }

    @Test("Title lookup returns the indexed title")
    func titleLookup() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha", "")])
        #expect(index.title(of: alphaID) == "Alpha")
    }

    // MARK: - Edge cases

    @Test("An empty index answers every query emptily")
    func emptyIndex() {
        let index = LinkIndex(entries: [])
        #expect(index.outgoing(from: alphaID).isEmpty)
        #expect(index.backlinks(to: alphaID).isEmpty)
        #expect(index.title(of: alphaID) == nil)
    }

    @Test("Duplicate titles resolve to one item rather than crashing")
    func duplicateTitles() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Same", ""),
            entry(betaID, "Same", ""),
            entry(gammaID, "Gamma", "[[Same]]"),
        ])
        #expect(index.outgoing(from: gammaID).count == 1)
    }

    @Test("Whitespace and case differences in titles still match")
    func titleTrimmedOnIndex() {
        let index = LinkIndex(entries: [
            entry(alphaID, "  Alpha  ", ""),
            entry(betaID, "Beta", "[[alpha]]"),
        ])
        #expect(index.outgoing(from: betaID) == [alphaID])
    }

    @Test("Unicode titles resolve")
    func unicodeTitles() {
        let index = LinkIndex(entries: [
            entry(alphaID, "会議メモ", ""),
            entry(betaID, "Beta", "see [[会議メモ]]"),
        ])
        #expect(index.outgoing(from: betaID) == [alphaID])
    }

    @Test("An aliased link resolves on its target, not its display text")
    func aliasResolvesOnTarget() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", "[[Beta|call it what you like]]"),
            entry(betaID, "Beta", ""),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
    }
}
