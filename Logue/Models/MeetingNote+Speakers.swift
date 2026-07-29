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

    /// Returns a copy with `Speaker` rows sharing a name collapsed onto the first row of each group.
    ///
    /// Speaker segments belonging to an absorbed row are re-attributed to the survivor, so no
    /// speaker data is lost. Transcript segments are untouched: they carry the name, which does not
    /// change here.
    ///
    /// Rows sharing a name are invisible in the speakers panel, which groups by name, so a
    /// redundant row cannot be selected and removed by hand. Meetings persisted before renaming
    /// merged still hold those pairs; this is what repairs them.
    func collapsingDuplicateSpeakers() -> MeetingNote {
        var survivorIDByName: [String: String] = [:]
        var survivorIDByAbsorbedID: [String: String] = [:]
        var survivors: [Speaker] = []

        for speaker in speakers {
            if let survivorID = survivorIDByName[speaker.name] {
                survivorIDByAbsorbedID[speaker.id] = survivorID
            } else {
                survivorIDByName[speaker.name] = speaker.id
                survivors.append(speaker)
            }
        }

        guard !survivorIDByAbsorbedID.isEmpty else { return self }

        var updated = self
        updated.speakers = survivors
        updated.speakerSegments = updated.speakerSegments.map { segment in
            guard let survivorID = survivorIDByAbsorbedID[segment.speakerId] else { return segment }
            // speakerId is a `let`, so re-attributing a segment means rebuilding it.
            return SpeakerSegment(
                id: segment.id,
                speakerId: survivorID,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                confidence: segment.confidence,
                embedding: segment.embedding
            )
        }
        return updated
    }

    /// Returns a copy with `oldName`'s speaker renamed to `newName`.
    ///
    /// When another speaker already holds `newName`, the two are merged instead of both keeping the
    /// name: transcript segments are relabelled, speaker segments are remapped onto the surviving
    /// speaker, and the redundant speaker row is dropped. That is what renaming to an existing name
    /// means in practice — diarization split one person in two and the user is putting them back
    /// together.
    ///
    /// Returns `self` unchanged when `newName` is blank or when no speaker is named `oldName`.
    ///
    /// Retyping the name a speaker already has is normally a no-op, but when two rows already share
    /// that name it is the one repair the user can express: the panel groups by name, so both rows
    /// appear as one and there is no id to target. In that case the rename is allowed through so the
    /// collapse below can run.
    func renamingSpeaker(from oldName: String, to newName: String) -> MeetingNote {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }

        let rowsHoldingOldName = speakers.filter { $0.name == oldName }.count
        guard rowsHoldingOldName > 0 else { return self }
        guard trimmed != oldName || rowsHoldingOldName > 1 else { return self }

        var updated = self

        for index in updated.segments.indices where updated.segments[index].speakerLabel == oldName {
            updated.segments[index].speakerLabel = trimmed
        }
        for index in updated.speakers.indices where updated.speakers[index].name == oldName {
            updated.speakers[index].name = trimmed
        }

        // Renaming onto a name another row already holds is a merge — diarization split one person
        // in two and the user is putting them back together. Renaming to an unused name leaves
        // nothing to collapse, so this is a no-op there.
        return updated.collapsingDuplicateSpeakers()
    }
}
