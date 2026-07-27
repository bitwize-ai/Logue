import Foundation
@testable import Logue
import Testing

/// Deciding what to do when the app's copy and the mirror file may both have moved.
///
/// A three-way comparison against the last synced state is what makes it possible to
/// tell "only the file changed" from "both changed". Without the base state every
/// difference would look like a conflict, or worse, one side would silently win.
@Suite("MirrorSyncDecision")
struct MirrorSyncDecisionTests {
    private let document = "---\n_logue_id: X\ntitle: A\n---\nbody\n"
    private let editedDocument = "---\n_logue_id: X\ntitle: A\n---\napp edit\n"
    private let editedFile = "---\n_logue_id: X\ntitle: A\n---\nfile edit\n"

    private func hash(_ text: String) -> String {
        MirrorSyncDecision.fingerprint(of: text)
    }

    // MARK: - First write

    @Test("A document with no file yet needs writing out")
    func missingFileNeedsWrite() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: nil, lastSyncedFingerprint: nil
        )
        #expect(decision == .writeFile)
    }

    @Test("A file that has vanished since the last sync is rewritten, not treated as a deletion")
    func deletedFileIsRewritten() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: nil, lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .writeFile)
    }

    // MARK: - No change

    @Test("Both sides matching the last sync means nothing to do")
    func inSync() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: document, lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .inSync)
    }

    @Test("Identical content with no recorded sync is adopted without a conflict")
    func identicalWithoutBaseIsInSync() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: document, lastSyncedFingerprint: nil
        )
        #expect(decision == .inSync)
    }

    // MARK: - One-sided changes

    @Test("Only the document changed, so the file is rewritten")
    func onlyDocumentChanged() {
        let decision = MirrorSyncDecision.decide(
            documentRender: editedDocument,
            fileContents: document,
            lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .writeFile)
    }

    @Test("Only the file changed, so the edit is applied to the document")
    func onlyFileChanged() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document,
            fileContents: editedFile,
            lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .applyFile)
    }

    // MARK: - Conflicts

    @Test("Both sides changed differently, which is a conflict")
    func bothChangedIsConflict() {
        let decision = MirrorSyncDecision.decide(
            documentRender: editedDocument,
            fileContents: editedFile,
            lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .conflict)
    }

    @Test("Both sides changed to the same content is not a conflict")
    func convergentChangeIsNotConflict() {
        let decision = MirrorSyncDecision.decide(
            documentRender: editedDocument,
            fileContents: editedDocument,
            lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .inSync)
    }

    /// Without a base state we cannot tell which side moved, so differing content is
    /// reported as a conflict rather than guessing. Losing an edit is worse than
    /// asking.
    @Test("Differing content with no recorded sync is a conflict, not a guess")
    func differingWithoutBaseIsConflict() {
        let decision = MirrorSyncDecision.decide(
            documentRender: editedDocument,
            fileContents: editedFile,
            lastSyncedFingerprint: nil
        )
        #expect(decision == .conflict)
    }

    // MARK: - Normalisation

    @Test("Line-ending differences alone are not a change")
    func lineEndingsIgnored() {
        let crlf = document.replacingOccurrences(of: "\n", with: "\r\n")
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: crlf, lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .inSync)
    }

    @Test("A trailing-newline difference alone is not a change")
    func trailingNewlineIgnored() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document,
            fileContents: document + "\n",
            lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .inSync)
    }

    @Test("An empty file is a change, not equivalent to no file")
    func emptyFileIsAChange() {
        let decision = MirrorSyncDecision.decide(
            documentRender: document, fileContents: "", lastSyncedFingerprint: hash(document)
        )
        #expect(decision == .applyFile)
    }

    // MARK: - Fingerprints

    @Test("The same text fingerprints the same")
    func fingerprintStable() {
        #expect(hash(document) == hash(document))
    }

    @Test("Different text fingerprints differently")
    func fingerprintDistinguishes() {
        #expect(hash(document) != hash(editedFile))
    }

    @Test("Fingerprints ignore line endings, matching the comparison")
    func fingerprintNormalises() {
        #expect(hash(document) == hash(document.replacingOccurrences(of: "\n", with: "\r\n")))
    }

    @Test("Unicode content fingerprints consistently")
    func fingerprintUnicode() {
        let text = "---\ntitle: 会議メモ\n---\n👩‍💻\n"
        #expect(hash(text) == hash(text))
    }
}
