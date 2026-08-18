import Foundation

/// The short form of a speaker's name, for the transcript gutter.
///
/// The gutter is a narrow column read vertically, so it needs a token of two or three characters
/// rather than a name. "Speaker 2" becomes "S2"; a person's name becomes their initials. It is a
/// label, not an identity — the full name stays available on hover and in the block header.
enum SpeakerShortLabel {
    static func forSpeaker(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // "Speaker 3" — the automatic naming — collapses to S3, which is what makes a column of
        // these readable at a glance.
        let words = trimmed.split(separator: " ")
        if words.count == 2,
           words[0].lowercased() == "speaker",
           words[1].allSatisfy(\.isNumber)
        {
            return "S\(words[1])"
        }

        // Otherwise initials, at most two, so the column keeps a predictable width.
        let initials = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        guard !initials.isEmpty else { return "" }
        return initials.joined()
    }
}
