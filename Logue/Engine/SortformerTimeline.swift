import Foundation

/// Cleans up raw Sortformer speaker output before it becomes persisted speaker data.
///
/// Sortformer emits a fragmented timeline: sub-second slivers, the same speaker split across
/// consecutive segments, brief alternations where one speaker's turn is interrupted and resumed,
/// and segments that overlap their neighbours. Feeding that straight into transcript alignment
/// produces speaker labels that flip mid-sentence.
///
/// Every step here is speaker-count agnostic. Nothing collapses the timeline towards a target
/// number of speakers, because a three- or four-person meeting is as valid as a two-person one.
enum SortformerTimeline {
    /// Filters fragments, merges same-speaker runs, collapses rapid alternations, and closes up
    /// overlaps and gaps. Returns segments ordered by start time.
    static func normalize(_ updates: [SortformerSpeakerUpdate]) -> [SortformerSpeakerUpdate] {
        guard !updates.isEmpty else { return [] }

        let ordered = updates
            .filter { $0.endTime - $0.startTime >= AppConstants.Diarization.minSpeakerSegmentDuration }
            .sorted { $0.startTime < $1.startTime }

        let merged = mergeAdjacentSameSpeaker(ordered)
        let collapsed = collapseRapidAlternations(merged)
        return enforceContinuity(mergeAdjacentSameSpeaker(collapsed))
    }

    // MARK: - Merging

    /// Joins consecutive segments attributed to the same speaker when the silence between them is
    /// shorter than `sameSpeakerMergeGap` — one continuous turn Sortformer reported in pieces.
    private static func mergeAdjacentSameSpeaker(
        _ updates: [SortformerSpeakerUpdate]
    ) -> [SortformerSpeakerUpdate] {
        updates.reduce(into: [SortformerSpeakerUpdate]()) { merged, update in
            guard let last = merged.last,
                  last.speakerIndex == update.speakerIndex,
                  update.startTime - last.endTime <= AppConstants.Diarization.sameSpeakerMergeGap
            else {
                merged.append(update)
                return
            }
            merged[merged.count - 1] = SortformerSpeakerUpdate(
                speakerIndex: last.speakerIndex,
                speakerName: last.speakerName,
                startTime: last.startTime,
                endTime: max(last.endTime, update.endTime)
            )
        }
    }

    // MARK: - Alternation collapsing

    /// Rewrites an A-B-A run that completes inside `alternationWindowSeconds` as a single segment
    /// belonging to whichever speaker holds more of it. Three turns in under a second is the model
    /// wavering, not two people talking.
    private static func collapseRapidAlternations(
        _ updates: [SortformerSpeakerUpdate]
    ) -> [SortformerSpeakerUpdate] {
        guard updates.count >= 3 else { return updates }

        var collapsed = updates
        var index = 0
        while index + 2 < collapsed.count {
            let first = collapsed[index]
            let middle = collapsed[index + 1]
            let last = collapsed[index + 2]

            let spansWindow = last.endTime - first.startTime <= AppConstants.Diarization.alternationWindowSeconds
            guard first.speakerIndex == last.speakerIndex,
                  first.speakerIndex != middle.speakerIndex,
                  spansWindow
            else {
                index += 1
                continue
            }

            let flankDuration = duration(of: first) + duration(of: last)
            let dominant = flankDuration >= duration(of: middle) ? first : middle
            collapsed.replaceSubrange(index ... index + 2, with: [SortformerSpeakerUpdate(
                speakerIndex: dominant.speakerIndex,
                speakerName: dominant.speakerName,
                startTime: first.startTime,
                endTime: last.endTime
            )])
            // Step back so a longer alternating run collapses from the inside out.
            index = max(0, index - 1)
        }
        return collapsed
    }

    // MARK: - Continuity

    /// Removes overlaps and oversized gaps so the timeline reads as one continuous conversation.
    /// A segment entirely swallowed by its predecessor is dropped rather than inverted.
    private static func enforceContinuity(
        _ updates: [SortformerSpeakerUpdate]
    ) -> [SortformerSpeakerUpdate] {
        var fixed: [SortformerSpeakerUpdate] = []
        fixed.reserveCapacity(updates.count)

        for update in updates {
            guard let last = fixed.last else {
                fixed.append(update)
                continue
            }

            var start = update.startTime
            if start < last.endTime {
                start = last.endTime
            } else if start - last.endTime > AppConstants.Diarization.timelineMaxGap {
                start = last.endTime + AppConstants.Diarization.timelineMaxGap
            }
            guard update.endTime > start else { continue }

            let adjusted = SortformerSpeakerUpdate(
                speakerIndex: update.speakerIndex,
                speakerName: update.speakerName,
                startTime: start,
                endTime: update.endTime
            )

            // Clamping can bring two same-speaker segments flush together.
            if last.speakerIndex == adjusted.speakerIndex {
                fixed[fixed.count - 1] = SortformerSpeakerUpdate(
                    speakerIndex: last.speakerIndex,
                    speakerName: last.speakerName,
                    startTime: last.startTime,
                    endTime: adjusted.endTime
                )
            } else {
                fixed.append(adjusted)
            }
        }
        return fixed
    }

    // MARK: - Helpers

    private static func duration(of update: SortformerSpeakerUpdate) -> TimeInterval {
        max(0, update.endTime - update.startTime)
    }
}
