import Foundation

// MARK: - Speaker Diarization

extension MeetingStore {
    func updateSpeakerData(for meetingID: UUID, speakers: [Speaker], speakerSegments: [SpeakerSegment]) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].speakers = speakers
        meetings[index].speakerSegments = speakerSegments
        meetings[index].hasSpeakerData = !speakerSegments.isEmpty

        // Only label transcript segments that don't already have a speaker label.
        // This preserves labels from previous recording sessions and periodic diarization.
        let speakerMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.name) })
        let sortedSpeakerSegs = speakerSegments.sorted { $0.startTime < $1.startTime }
        // Pre-extract startTimes for binary search (O(n log n) vs O(n²))
        let startTimes = sortedSpeakerSegs.map(\.startTime)

        guard !sortedSpeakerSegs.isEmpty else { return }

        for (segIdx, segment) in meetings[index].segments.enumerated() {
            guard segment.speakerLabel == nil else { continue }

            let midpoint = (segment.startTime + segment.endTime) / 2

            // Binary search for the insertion point of midpoint in sorted speaker segments.
            // lo ends up as the first index where startTime > midpoint.
            var lo = 0, hi = startTimes.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if startTimes[mid] <= midpoint {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            var matchedName: String?
            var bestDistance = Double.greatestFiniteMagnitude
            let searchRange = max(0, lo - 2) ... min(sortedSpeakerSegs.count - 1, lo + 1)

            for i in searchRange {
                let ss = sortedSpeakerSegs[i]
                if midpoint >= ss.startTime, midpoint <= ss.endTime {
                    matchedName = speakerMap[ss.speakerId]
                    break
                }
                let distance = min(abs(midpoint - ss.startTime), abs(midpoint - ss.endTime))
                if distance < bestDistance, distance <= AppConstants.Diarization.speakerLabelTolerance {
                    bestDistance = distance
                    matchedName = speakerMap[ss.speakerId]
                }
            }

            if let name = matchedName {
                meetings[index].segments[segIdx].speakerLabel = name
            }
        }

        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    /// Replace all transcript segments with the output of batch ASR (Parakeet TDT).
    /// Called after recording stops to upgrade streaming transcript quality.
    func replaceTranscript(for meetingID: UUID, with segments: [TranscriptSegment]) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].segments = segments.sorted { $0.startTime < $1.startTime }
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}
