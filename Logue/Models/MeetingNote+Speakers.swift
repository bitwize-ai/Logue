import Foundation
import SwiftUI

// MARK: - Speaker Naming

extension MeetingNote {
    /// Speaker display colours keyed by speaker name.
    ///
    /// Names are not unique — diarization can split one person across two rows, and the user may
    /// rename both to the same person. Duplicate names collapse to the first speaker's colour
    /// rather than trapping, which also lets meetings already persisted with duplicate names open.
    var speakerColorsByName: [String: Color] {
        Dictionary(speakers.map { ($0.name, $0.displayColor) }, uniquingKeysWith: { first, _ in first })
    }

    /// Returns a copy with `oldName`'s speaker renamed to `newName`.
    ///
    /// When another speaker already holds `newName`, the two are merged instead of both keeping the
    /// name: transcript segments are relabelled, speaker segments are remapped onto the surviving
    /// speaker, and the redundant speaker row is dropped. That is what renaming to an existing name
    /// means in practice — diarization split one person in two and the user is putting them back
    /// together.
    ///
    /// Returns `self` unchanged when `newName` is blank, unchanged from `oldName`, or when no
    /// speaker is named `oldName`.
    func renamingSpeaker(from oldName: String, to newName: String) -> MeetingNote {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return self }
        guard speakers.contains(where: { $0.name == oldName }) else { return self }

        var updated = self

        for index in updated.segments.indices where updated.segments[index].speakerLabel == oldName {
            updated.segments[index].speakerLabel = trimmed
        }

        guard let survivor = updated.speakers.first(where: { $0.name == trimmed }) else {
            for index in updated.speakers.indices where updated.speakers[index].name == oldName {
                updated.speakers[index].name = trimmed
            }
            return updated
        }

        let absorbedIDs = Set(updated.speakers.filter { $0.name == oldName }.map(\.id))
        updated.speakerSegments = updated.speakerSegments.map { segment in
            guard absorbedIDs.contains(segment.speakerId) else { return segment }
            // speakerId is a `let`, so re-attributing a segment means rebuilding it.
            return SpeakerSegment(
                id: segment.id,
                speakerId: survivor.id,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                confidence: segment.confidence,
                embedding: segment.embedding
            )
        }
        updated.speakers.removeAll { absorbedIDs.contains($0.id) }

        return updated
    }
}
