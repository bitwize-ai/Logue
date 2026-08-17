import Foundation

/// Pours the batch transcriber's words into the live transcript's shape.
///
/// The post-recording pass reads the whole recording at once and is markedly more accurate than the
/// live transcriber — it is what turns "that ours came in higher" into "Quarterly numbers came in
/// higher". But its sentence boundaries are its own, so adopting its output wholesale re-cut the
/// transcript the user had been reading: a different number of blocks, text merged and split, their
/// place lost, a minute after they stopped.
///
/// Both are timed against the same recording, so neither has to be thrown away. Each word is placed
/// in the live segment whose stretch of time contains it, and every segment keeps its identity, its
/// start and its end. The reader sees better words appear in the lines they already had.
enum TranscriptRealignment {
    /// A word from the batch transcriber, timed against the session.
    struct TimedWord: Equatable {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval

        init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }

        /// Placed by its midpoint: a word straddling a boundary belongs to whichever side holds
        /// most of it, and every word lands in exactly one segment.
        var midpoint: TimeInterval {
            (startTime + endTime) / 2
        }
    }

    /// Joins the transcriber's sub-word tokens into whole words.
    ///
    /// Parakeet emits pieces, not words: "Hundreds" arrives as "H" + "undreds", "theCUBE" as
    /// "theCU" + "BE". Placing those pieces individually let a single word be split across two
    /// lines, which is how a transcript ends up reading "H / undreds of other businesses".
    ///
    /// A piece that begins a new word carries a leading space; anything else continues the word
    /// before it. The joined word spans from its first piece's start to its last piece's end, so it
    /// still lands in exactly one line.
    static func words(fromTokens tokens: [TimedWord]) -> [TimedWord] {
        var words: [TimedWord] = []
        var pending: [TimedWord] = []

        func flush() {
            guard let first = pending.first, let last = pending.last else { return }
            let text = pending.map(\.text).joined()
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                pending.removeAll()
                return
            }
            words.append(TimedWord(text: text, startTime: first.startTime, endTime: last.endTime))
            pending.removeAll()
        }

        for token in tokens {
            let startsWord = token.text.first.map { $0 == " " || $0 == "\u{2581}" } ?? false
            if startsWord {
                flush()
            }
            pending.append(token)
        }
        flush()
        return words
    }

    /// Returns the live segments with their text replaced by the batch words that fall inside them.
    ///
    /// Segments keep their `id`, `startTime`, `endTime` and speaker. A segment no word lands in
    /// keeps the text it already had — blanking a line the user watched being written would be a
    /// worse outcome than leaving it as the live transcriber heard it.
    /// - Parameter sessionStart: where this recording session begins on the meeting's timeline.
    ///   Batch words are timed from the start of the session's own audio, while segments are timed
    ///   from the start of the *meeting* — a second session on the same meeting starts its words at
    ///   zero while its lines are stamped minutes in. Without this shift every word of session two
    ///   lands in session one's lines and overwrites them.
    static func realign(
        live: [TranscriptSegment],
        words: [TimedWord],
        sessionStart: TimeInterval = 0
    ) -> [TranscriptSegment] {
        guard !live.isEmpty, !words.isEmpty else { return live }

        let words = sessionStart == 0 ? words : words.map { word in
            TimedWord(
                text: word.text,
                startTime: word.startTime + sessionStart,
                endTime: word.endTime + sessionStart
            )
        }

        // Only this session's lines may receive this session's words. Shifting the words is not
        // enough on its own: a session that produced no live lines of its own — the speech gate
        // admitting nothing, or the transcriber erroring — leaves every shifted word past the end
        // of every earlier line, and the nearest-segment fallback has no distance cap, so the
        // whole second session was concatenated into the last line of the first. Five minutes of
        // correct transcript then read as the wrong session.
        let candidates = live.indices.filter { live[$0].startTime >= sessionStart }
        guard !candidates.isEmpty else { return live }

        // Paired with their positions before sorting, so a word can be attributed back to the
        // segment it belongs to whatever order the times arrive in.
        let ordered = candidates
            .map { (offset: $0, element: live[$0]) }
            .sorted { $0.element.startTime < $1.element.startTime }
        var collected: [Int: [String]] = [:]

        for word in words {
            guard let index = indexOfSegment(containing: word.midpoint, in: ordered) else { continue }
            collected[index, default: []].append(word.text)
        }

        return live.indices.map { index in
            let segment = live[index]
            guard let parts = collected[index] else { return segment }
            let text = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return segment }

            var updated = segment
            updated.text = text
            return updated
        }
    }

    /// Moves text across line boundaries so each line ends where a sentence does.
    ///
    /// Placing words by time puts them in the right line but cuts them in the wrong place: the live
    /// boundaries were sentence ends in the *live* wording, and the batch wording reaches those
    /// moments mid-phrase. So a line ends "Okay, so let's" and the next opens "use this agent".
    ///
    /// The number of lines, their identities and their times are all left alone — only where the
    /// text is cut moves, and only far enough to reach the sentence end already sitting nearby.
    static func snappedToSentences(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.count > 1 else { return segments }
        var result = segments

        for index in 0 ..< (result.count - 1) {
            let current = result[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !current.isEmpty, !endsSentence(current) else { continue }

            let next = result[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cut = sentenceEnd(in: next) else { continue }

            let moved = String(next[next.startIndex ... cut]).trimmingCharacters(in: .whitespaces)
            let remainder = String(next[next.index(after: cut)...]).trimmingCharacters(in: .whitespaces)
            // Never empty a line: a blank line is a worse artefact than a line ending early.
            guard !moved.isEmpty, !remainder.isEmpty else { continue }

            result[index].text = current + " " + moved
            result[index + 1].text = remainder
        }
        return result
    }

    /// How far into a line we will look for a sentence end before leaving the cut where it is.
    ///
    /// Far enough to catch a clause that ran over, short enough that a line never swallows the one
    /// after it.
    private static let sentenceSearchLimit = 80

    private static func sentenceEnd(in text: String) -> String.Index? {
        var offset = 0
        for index in text.indices {
            if offset >= sentenceSearchLimit {
                return nil
            }
            if ".!?".contains(text[index]) {
                return index
            }
            offset += 1
        }
        return nil
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".!?…".contains(last)
    }

    /// The segment whose span contains `time`, or the nearest one when it falls in a gap.
    ///
    /// Words do land outside every segment: the live transcriber leaves silence between lines, and
    /// the batch pass hears things in it. Dropping them would lose real speech, so they attach to
    /// the closest line rather than disappearing.
    private static func indexOfSegment(
        containing time: TimeInterval,
        in ordered: [(offset: Int, element: TranscriptSegment)]
    ) -> Int? {
        guard !ordered.isEmpty else { return nil }

        for entry in ordered where time >= entry.element.startTime && time < entry.element.endTime {
            return entry.offset
        }

        var nearest = ordered[0]
        var nearestDistance = TimeInterval.greatestFiniteMagnitude
        for entry in ordered {
            let distance = time < entry.element.startTime
                ? entry.element.startTime - time
                : time - entry.element.endTime
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = entry
            }
        }
        return nearest.offset
    }
}
