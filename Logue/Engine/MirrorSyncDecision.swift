import CryptoKit
import Foundation

/// What to do when the app's copy of a document and its mirror file may both have
/// changed.
///
/// Decided by a three-way comparison against the last synced state. That base is what
/// makes "only the file changed" distinguishable from "both changed" — without it,
/// either every difference looks like a conflict, or one side silently wins and an
/// edit is lost.
enum MirrorSyncDecision: Equatable, Sendable {
    /// Nothing to do — both sides agree.
    case inSync
    /// The app's copy is authoritative for this change; write it out.
    case writeFile
    /// The file was edited externally; apply it to the document.
    case applyFile
    /// Both sides moved independently. Needs the user to choose.
    case conflict

    /// Decides what to do for one document.
    ///
    /// - Parameters:
    ///   - documentRender: what the document currently renders to.
    ///   - fileContents: the mirror file on disk, or `nil` if absent.
    ///   - lastSyncedFingerprint: fingerprint of the content both sides last agreed
    ///     on, or `nil` if they never have.
    static func decide(
        documentRender: String,
        fileContents: String?,
        lastSyncedFingerprint: String?
    ) -> MirrorSyncDecision {
        // No file: write one. A file that has disappeared since the last sync is
        // rewritten rather than read as a deletion — deleting the mirror should not
        // delete the document.
        guard let fileContents else { return .writeFile }

        let documentPrint = fingerprint(of: documentRender)
        let filePrint = fingerprint(of: fileContents)

        if documentPrint == filePrint {
            return .inSync
        }

        guard let lastSyncedFingerprint else {
            // Never synced and the two differ: we cannot tell which side moved, so ask
            // rather than guess. Losing an edit is worse than a prompt.
            return .conflict
        }

        let documentChanged = documentPrint != lastSyncedFingerprint
        let fileChanged = filePrint != lastSyncedFingerprint

        switch (documentChanged, fileChanged) {
        case (true, true): return .conflict
        case (true, false): return .writeFile
        case (false, true): return .applyFile
        case (false, false): return .inSync // unreachable: prints differ
        }
    }

    /// A stable fingerprint of mirror content.
    ///
    /// Normalises line endings and trailing newlines first, so a file rewritten by
    /// another editor with different conventions does not read as an edit.
    static func fingerprint(of text: String) -> String {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalised.hasSuffix("\n")
            ? String(normalised.reversed().drop(while: { $0 == "\n" }).reversed())
            : normalised

        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
