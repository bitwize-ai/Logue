import Foundation

/// Derives document filenames from document titles.
///
/// Titles are user-controlled and these files land in a user-visible directory, so
/// this is a path-safety boundary: nothing derived from a title may contain a path
/// separator or escape the documents folder.
///
/// Filenames are for humans — the authoritative link back to a document is the
/// `_logue_id` inside the file, so a file can be renamed freely without breaking.
enum DocumentFilename {
    static let fileExtension = "md"

    /// Byte budget for the whole filename including the extension.
    ///
    /// Most filesystems cap a component at 255 bytes; staying well under leaves room
    /// for a disambiguating suffix and for filesystems that count differently.
    static let maxFilenameBytes = 180

    private static let fallbackStem = "Untitled"

    /// A safe filename for `document`, avoiding any name in `taken`.
    /// A safe filename for `document`, avoiding any name in `taken`.
    ///
    /// `taken` is matched **case-insensitively**, because the filesystems this ships on are.
    /// `uniqueTitle` deduplicates titles case-sensitively, so `Notes` and `notes` coexist in real
    /// libraries — and a case-sensitive check here let the second one resolve to a name `taken` did
    /// not contain, so `write(to:atomically:)` replaced the first document's file. `verify()` then
    /// read back the winner and passed, the mode flipped, and the loser's markdown was gone with no
    /// Trash copy.
    static func filename(for document: WritingDocument, avoiding taken: Set<String> = []) -> String {
        let folded = Set(taken.map { $0.lowercased() })
        func isFree(_ name: String) -> Bool {
            !folded.contains(name.lowercased())
        }

        let stem = safeStem(from: document.title)
        let candidate = "\(stem).\(fileExtension)"
        guard !isFree(candidate) else { return candidate }

        // Disambiguate with a prefix of the document identifier: stable for a given
        // document, so a collision does not produce a different name on every save.
        let shortID = document.id.uuidString.prefix(8)
        let disambiguated = "\(stem) (\(shortID)).\(fileExtension)"
        guard !isFree(disambiguated) else { return disambiguated }

        // Fall back to the full identifier, which cannot collide.
        return "\(stem) (\(document.id.uuidString)).\(fileExtension)"
    }

    // MARK: - Private

    /// Strips everything unsafe or confusing from a title.
    private static func safeStem(from title: String) -> String {
        var cleaned = ""
        for character in title {
            if character.isNewline {
                continue
            }
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                continue
            }
            // `/` and `:` are path separators on Apple platforms; the rest are
            // reserved or troublesome across filesystems and shells.
            if "/:\\?%*|\"<>".contains(character) {
                continue
            }
            cleaned.append(character)
        }

        // A leading dot would hide the file; a leading dash reads as a flag.
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") || cleaned.hasPrefix("-") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return fallbackStem }
        return truncated(cleaned)
    }

    /// Truncates on character boundaries so a multi-byte character is never split.
    private static func truncated(_ stem: String) -> String {
        let budget = maxFilenameBytes - (fileExtension.utf8.count + 1)
        guard stem.utf8.count > budget else { return stem }

        var result = ""
        for character in stem {
            if result.utf8.count + String(character).utf8.count > budget {
                break
            }
            result.append(character)
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallbackStem : trimmed
    }
}
