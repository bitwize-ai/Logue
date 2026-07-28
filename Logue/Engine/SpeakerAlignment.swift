import Foundation

/// Attributes transcript segments to speakers by time overlap.
///
/// Replaces midpoint-nearest matching, which asks only "which speaker segment is closest to the
/// middle of this transcript segment?" — a question whose answer is wrong whenever a brief
/// interjection happens to land mid-sentence, and whose 3.5s search window will happily borrow a
/// speaker who was not talking at all.
///
/// Segments that already carry a label are left completely alone: not split, not relabelled, not
/// smoothed. That protects the "You" attribution given to local mic audio in online meetings, and
/// any speaker the user has corrected by hand.
enum SpeakerAlignment {
    /// Splits transcript segments at speaker boundaries, labels the unlabelled ones by overlap
    /// vote, then smooths brief single-segment islands.
    ///
    /// Never returns fewer segments than it was given — a transcript segment may be subdivided but
    /// is never dropped.
    static func align(
        segments: [TranscriptSegment],
        speakerSegments: [SpeakerSegment],
        speakerNamesByID: [String: String]
    ) -> [TranscriptSegment] {
        guard !segments.isEmpty, !speakerSegments.isEmpty else { return segments }

        let sortedSpeakers = speakerSegments
            .filter { $0.endTime > $0.startTime && speakerNamesByID[$0.speakerId] != nil }
            .sorted { $0.startTime < $1.startTime }
        guard !sortedSpeakers.isEmpty else { return segments }

        let protectedIDs = Set(segments.filter { $0.speakerLabel != nil }.map(\.id))

        var output = split(
            segments: segments,
            protectedIDs: protectedIDs,
            speakerSegments: sortedSpeakers,
            speakerNamesByID: speakerNamesByID
        )

        var previousLabel: String?
        for index in output.indices {
            guard output[index].speakerLabel == nil else {
                previousLabel = output[index].speakerLabel
                continue
            }
            let label = vote(
                from: output[index].startTime,
                to: output[index].endTime,
                speakerSegments: sortedSpeakers,
                speakerNamesByID: speakerNamesByID,
                previousLabel: previousLabel
            )
            output[index].speakerLabel = label
            previousLabel = label
        }

        return smoothIslands(output, protectedIDs: protectedIDs)
    }

    // MARK: - Overlap voting

    /// Picks the speaker holding the most of `[start, end]`.
    ///
    /// Segments longer than `chunkThresholdSeconds` are subdivided and each slice votes weighted by
    /// its duration, so a long segment straddling a speaker change is decided by how much of it each
    /// speaker actually holds rather than by whatever sits at its midpoint.
    private static func vote(
        from start: TimeInterval,
        to end: TimeInterval,
        speakerSegments: [SpeakerSegment],
        speakerNamesByID: [String: String],
        previousLabel: String?
    ) -> String? {
        guard end - start > AppConstants.Diarization.chunkThresholdSeconds else {
            return winner(
                from: start, to: end,
                speakerSegments: speakerSegments,
                speakerNamesByID: speakerNamesByID,
                previousLabel: previousLabel
            )
        }

        var votes: [String: TimeInterval] = [:]
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(chunkStart + AppConstants.Diarization.chunkDurationSeconds, end)
            // Chunks vote without continuity bias; the aggregate below applies it once.
            if let chunkWinner = winner(
                from: chunkStart, to: chunkEnd,
                speakerSegments: speakerSegments,
                speakerNamesByID: speakerNamesByID,
                previousLabel: nil
            ) {
                votes[chunkWinner, default: 0] += chunkEnd - chunkStart
            }
            chunkStart = chunkEnd
        }

        let ranked = votes.sorted { $0.value > $1.value }
        guard let best = ranked.first else { return nil }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        if isTooCloseToCall(best: best.value, runnerUp: runnerUp), let previousLabel {
            return previousLabel
        }
        return best.key
    }

    /// Greatest-overlap speaker for one interval, falling back to the nearest speaker within
    /// `labelFallbackTolerance` when nothing overlaps at all.
    private static func winner(
        from start: TimeInterval,
        to end: TimeInterval,
        speakerSegments: [SpeakerSegment],
        speakerNamesByID: [String: String],
        previousLabel: String?
    ) -> String? {
        var bestName: String?
        var bestOverlap: TimeInterval = 0
        var runnerUpOverlap: TimeInterval = 0
        var nearestName: String?
        var nearestDistance = TimeInterval.greatestFiniteMagnitude

        for speakerSegment in speakerSegments {
            if speakerSegment.startTime > end + AppConstants.Diarization.labelFallbackTolerance {
                break
            }
            guard let name = speakerNamesByID[speakerSegment.speakerId] else { continue }

            let overlap = min(end, speakerSegment.endTime) - max(start, speakerSegment.startTime)
            if overlap > bestOverlap {
                runnerUpOverlap = bestOverlap
                bestOverlap = overlap
                bestName = name
            } else if overlap > runnerUpOverlap {
                runnerUpOverlap = overlap
            }

            let distance = distanceBetween(start: start, end: end, speakerSegment: speakerSegment)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestName = name
            }
        }

        guard bestOverlap > 0 else {
            return nearestDistance <= AppConstants.Diarization.labelFallbackTolerance ? nearestName : nil
        }
        if isTooCloseToCall(best: bestOverlap, runnerUp: runnerUpOverlap), let previousLabel {
            return previousLabel
        }
        return bestName
    }

    /// A runner-up this close to the winner means the interval genuinely spans both speakers, so
    /// picking the marginal winner is a coin flip. Continuity is the better guess.
    private static func isTooCloseToCall(best: TimeInterval, runnerUp: TimeInterval) -> Bool {
        runnerUp > 0 && runnerUp >= best * AppConstants.Diarization.ambiguityOverlapRatio
    }

    private static func distanceBetween(
        start: TimeInterval,
        end: TimeInterval,
        speakerSegment: SpeakerSegment
    ) -> TimeInterval {
        if end < speakerSegment.startTime {
            return speakerSegment.startTime - end
        }
        if start > speakerSegment.endTime {
            return start - speakerSegment.endTime
        }
        return 0
    }

    // MARK: - Splitting at speaker boundaries

    private static func split(
        segments: [TranscriptSegment],
        protectedIDs: Set<UUID>,
        speakerSegments: [SpeakerSegment],
        speakerNamesByID: [String: String]
    ) -> [TranscriptSegment] {
        segments.flatMap { segment -> [TranscriptSegment] in
            guard !protectedIDs.contains(segment.id) else { return [segment] }
            return splitParts(
                of: segment,
                speakerSegments: speakerSegments,
                speakerNamesByID: speakerNamesByID
            ) ?? [segment]
        }
    }

    /// Divides one transcript segment at the boundaries between the speakers it spans.
    ///
    /// Returns `nil` — meaning "leave this segment whole" — whenever a faithful split is not
    /// possible: only one speaker involved, too many speakers, parts that would be too short, or
    /// fewer words than parts. Splitting must never invent, duplicate, or discard text, so when in
    /// doubt the original segment is kept.
    private static func splitParts(
        of segment: TranscriptSegment,
        speakerSegments: [SpeakerSegment],
        speakerNamesByID: [String: String]
    ) -> [TranscriptSegment]? {
        let ranges = speakerRanges(spanning: segment, speakerSegments: speakerSegments)
        guard ranges.count > 1, ranges.count <= AppConstants.Diarization.maxSplitParts else { return nil }

        // Butt each part against the next so the split covers the original span with no holes.
        var bounds: [(start: TimeInterval, end: TimeInterval, speakerId: String)] = []
        for (index, range) in ranges.enumerated() {
            let start = index == 0 ? segment.startTime : bounds[index - 1].end
            let end = index == ranges.count - 1 ? segment.endTime : range.end
            guard end - start >= AppConstants.Diarization.minSplitPartDuration else { return nil }
            bounds.append((start: start, end: end, speakerId: range.speakerId))
        }

        let words = segment.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let texts = distribute(words: words, across: bounds.map { $0.end - $0.start }) else { return nil }

        return zip(bounds, texts).map { bound, text in
            TranscriptSegment(
                text: text,
                startTime: bound.start,
                endTime: bound.end,
                speakerLabel: speakerNamesByID[bound.speakerId],
                confidence: segment.confidence,
                audioSource: segment.audioSource
            )
        }
    }

    /// Speaker ranges overlapping `segment` by a meaningful margin, clipped to its bounds and with
    /// consecutive runs of the same speaker merged.
    private static func speakerRanges(
        spanning segment: TranscriptSegment,
        speakerSegments: [SpeakerSegment]
    ) -> [(start: TimeInterval, end: TimeInterval, speakerId: String)] {
        var ranges: [(start: TimeInterval, end: TimeInterval, speakerId: String)] = []
        for speakerSegment in speakerSegments {
            if speakerSegment.startTime >= segment.endTime {
                break
            }
            guard speakerSegment.endTime > segment.startTime else { continue }

            let start = max(segment.startTime, speakerSegment.startTime)
            let end = min(segment.endTime, speakerSegment.endTime)
            guard end - start >= AppConstants.Diarization.minSplitOverlap else { continue }

            if let last = ranges.last, last.speakerId == speakerSegment.speakerId {
                ranges[ranges.count - 1].end = max(last.end, end)
            } else {
                ranges.append((start: start, end: end, speakerId: speakerSegment.speakerId))
            }
        }
        return ranges
    }

    /// Allocates words across parts in proportion to their durations, guaranteeing every part at
    /// least one word. Returns `nil` when there are fewer words than parts.
    private static func distribute(words: [String], across durations: [TimeInterval]) -> [String]? {
        guard words.count >= durations.count, durations.count > 1 else { return nil }
        let total = durations.reduce(0, +)
        guard total > 0 else { return nil }

        var parts: [String] = []
        parts.reserveCapacity(durations.count)
        var cursor = 0
        var elapsed: TimeInterval = 0

        for (index, duration) in durations.enumerated() {
            let partsRemaining = durations.count - index - 1
            let end: Int
            if partsRemaining == 0 {
                end = words.count
            } else {
                elapsed += duration
                let proportional = Int((Double(words.count) * elapsed / total).rounded())
                end = min(max(proportional, cursor + 1), words.count - partsRemaining)
            }
            guard end > cursor else { return nil }
            parts.append(words[cursor ..< end].joined(separator: " "))
            cursor = end
        }
        return parts
    }

    // MARK: - Smoothing

    /// Rewrites a lone segment flanked on both sides by the same other speaker.
    ///
    /// Bounded to islands shorter than `maxSmoothedIslandDuration`: a two-second turn is somebody
    /// speaking, and overriding it would delete a real contribution. Only brief islands are treated
    /// as diarization flapping. Protected segments are never rewritten.
    private static func smoothIslands(
        _ segments: [TranscriptSegment],
        protectedIDs: Set<UUID>
    ) -> [TranscriptSegment] {
        guard segments.count >= 3 else { return segments }

        var smoothed = segments
        for index in 1 ..< smoothed.count - 1 {
            guard !protectedIDs.contains(smoothed[index].id),
                  let current = smoothed[index].speakerLabel,
                  let previous = smoothed[index - 1].speakerLabel,
                  let next = smoothed[index + 1].speakerLabel,
                  current != previous,
                  previous == next,
                  smoothed[index].endTime - smoothed[index].startTime
                  <= AppConstants.Diarization.maxSmoothedIslandDuration
            else { continue }
            smoothed[index].speakerLabel = previous
        }
        return smoothed
    }
}
