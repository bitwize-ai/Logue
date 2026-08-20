import Foundation

/// Puts an AI highlight at the moment it is actually about.
///
/// The model is asked for a label and a timestamp, but it cannot hear the recording — it is reading
/// a transcript and estimating the number. The estimates cluster, which is why a meeting's
/// highlights all land in its first minute. A highlight is a way of jumping to a moment, so one
/// pointing at the wrong minute is worse than none at all.
///
/// The transcript does know when things were said. Matching a highlight's words against it puts the
/// mark where the words are, and the model's guess is used only when nothing matches.
enum HighlightAnchor {
    /// Words too common to carry meaning; matching on them would anchor everything to the longest
    /// line rather than the relevant one.
    private static let ignored: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with", "is", "are",
        "was", "were", "it", "its", "this", "that", "these", "those", "as", "at", "by", "from",
        "you", "your", "we", "our", "they", "their", "i", "he", "she", "be", "been", "has", "have",
    ]

    static func anchored(_ highlights: [Bookmark], to segments: [TranscriptSegment]) -> [Bookmark] {
        guard !segments.isEmpty else { return highlights }
        return highlights.map { anchor($0, to: segments) }
    }

    private static func anchor(_ highlight: Bookmark, to segments: [TranscriptSegment]) -> Bookmark {
        let wanted = significantWords(in: highlight.label)
        guard !wanted.isEmpty else { return highlight }

        var best: (segment: TranscriptSegment, score: Int)?
        for segment in segments {
            let present = significantWords(in: segment.text)
            guard !present.isEmpty else { continue }
            let score = wanted.intersection(present).count
            if score > (best?.score ?? 0) {
                best = (segment, score)
            }
        }

        // A single word in common is coincidence, not a match. Below that bar the model's own
        // estimate is no worse, and at least it is not confidently wrong somewhere else.
        guard let best, best.score >= 2 else { return highlight }

        return Bookmark(
            id: highlight.id,
            label: highlight.label,
            timestamp: best.segment.startTime,
            createdAt: highlight.createdAt,
            color: highlight.color,
            source: highlight.source
        )
    }

    private static func significantWords(in text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        let words = text.lowercased()
            .components(separatedBy: separators)
            .filter { $0.count > 2 && !ignored.contains($0) }
        return Set(words)
    }
}
