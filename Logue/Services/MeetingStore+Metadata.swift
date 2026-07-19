import Foundation

// MARK: - Document Linkage

extension MeetingStore {
    /// Returns the meeting whose `summaryDocumentID` points at `documentID`, if any.
    /// Used by the document editor to show a "From meeting" back-link — the reverse direction
    /// of the forward link already surfaced in `MeetingSummaryPanelView`.
    func meetingLinked(toDocument documentID: UUID) -> MeetingNote? {
        activeMeetings.first { $0.summaryDocumentID == documentID }
    }
}

// MARK: - Bookmarks

extension MeetingStore {
    func addBookmark(_ bookmark: Bookmark, to meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].bookmarks.append(bookmark)
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func removeBookmark(bookmarkID: UUID, from meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].bookmarks.removeAll { $0.id == bookmarkID }
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func updateBookmark(_ bookmark: Bookmark, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let bookmarkIndex = meetings[mIdx].bookmarks.firstIndex(where: { $0.id == bookmark.id })
        else { return }
        meetings[mIdx].bookmarks[bookmarkIndex] = bookmark
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}

// MARK: - Tags

extension MeetingStore {
    func addTag(_ tag: String, to meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !meetings[index].tags.contains(trimmed) else { return }
        meetings[index].tags.append(trimmed)
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func removeTag(_ tag: String, from meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].tags.removeAll { $0 == tag }
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    var allTags: [String] {
        if let cached = cachedAllTags {
            return cached
        }
        let result = Array(Set(meetings.flatMap(\.tags))).sorted()
        cachedAllTags = result
        return result
    }
}
