import Foundation

/// An unresolved disagreement between a document and its mirror file.
///
/// Kept as data rather than resolved automatically: both sides represent real work,
/// so the user chooses. Held in memory only — a conflict is re-detected on the next
/// sync pass, and persisting a stale one would be worse than re-deriving it.
struct MirrorConflict: Identifiable, Equatable, Sendable {
    var id: UUID {
        documentID
    }

    let documentID: UUID
    /// Title at the time of detection, for listing conflicts without a store lookup.
    let documentTitle: String
    /// What the app would write.
    let appVersion: String
    /// What is on disk.
    let fileVersion: String
    /// Path of the mirror file, for "reveal in Finder".
    let fileURL: URL
    let detectedAt: Date

    /// How the user resolved it.
    enum Resolution: Equatable, Sendable {
        /// Keep the app's copy and overwrite the file.
        case keepApp
        /// Take the file's contents into the document.
        case keepFile
    }

    /// The body text of each side, for a readable comparison.
    ///
    /// Frontmatter is stripped because a metadata-only difference is not what the user
    /// is being asked to adjudicate, and showing YAML in a diff obscures the prose.
    var appBody: String {
        MarkdownFrontmatter.parse(appVersion).body
    }

    var fileBody: String {
        MarkdownFrontmatter.parse(fileVersion).body
    }

    /// Whether the two differ in their prose, as opposed to only in metadata.
    var differsInBody: Bool {
        MirrorSyncDecision.fingerprint(of: appBody) != MirrorSyncDecision.fingerprint(of: fileBody)
    }
}
