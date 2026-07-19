import Foundation

// MARK: - Topic Keywords & Related Meetings

extension MeetingStore {
    func setTopicKeywords(_ keywords: [String], for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].topicKeywords = keywords
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
        MeetingMemoryIndex.shared.indexMeeting(meetings[index])
    }

    func relatedMeetings(to meetingID: UUID, limit: Int = 5) -> [MeetingNote] {
        guard let index = meetingIndex(for: meetingID) else { return [] }
        let meeting = meetings[index]
        guard !meeting.topicKeywords.isEmpty else { return [] }

        // Build inverted index on the fly: keyword → [meetingIndex]
        var keywordIndex: [String: [Int]] = [:]
        for (i, other) in meetings.enumerated() where other.id != meetingID && !other.isArchived && !other.isTrashed {
            for kw in other.topicKeywords {
                keywordIndex[kw.lowercased(), default: []].append(i)
            }
        }

        // Score by counting keyword overlaps
        var scores: [UUID: Int] = [:]
        for kw in meeting.topicKeywords {
            if let indices = keywordIndex[kw.lowercased()] {
                for i in indices {
                    scores[meetings[i].id, default: 0] += 1
                }
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { entry in meetings.first { $0.id == entry.key } }
    }

    /// Search meetings using FTS5 index for transcript/summary, with title/tag fallback.
    func searchMeetings(query: String) async -> [MeetingNote] {
        let ftsIDs = await MeetingMemoryIndex.shared.searchMatchingIDs(query: query)
        let lowered = query.lowercased()
        return activeMeetings.filter { meeting in
            meeting.title.lowercased().contains(lowered)
                || (meeting.summary?.lowercased().contains(lowered) ?? false)
                || meeting.tags.contains { $0.lowercased().contains(lowered) }
                || ftsIDs.contains(meeting.id)
        }
    }
}

// MARK: - Search with Snippets

extension MeetingStore {
    /// Returns meetings with matching text snippets for display.
    func searchWithSnippets(query: String) -> [(meeting: MeetingNote, matchType: String, snippet: String)] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        var results: [(meeting: MeetingNote, matchType: String, snippet: String)] = []

        for meeting in meetings where !meeting.isArchived && !meeting.isTrashed {
            if meeting.title.lowercased().contains(lowered) {
                results.append((meeting, "Title", meeting.title))
            } else if let summary = meeting.summary, summary.lowercased().contains(lowered) {
                let snippet = extractSnippet(from: summary, around: lowered)
                results.append((meeting, "Summary", snippet))
            } else if let segment = meeting.segments.first(where: { $0.text.lowercased().contains(lowered) }) {
                let snippet = extractSnippet(from: segment.text, around: lowered)
                results.append((meeting, "Transcript", snippet))
            } else if let item = meeting.actionItems.first(where: { $0.title.lowercased().contains(lowered) }) {
                results.append((meeting, "Action Item", item.title))
            } else if let tag = meeting.tags.first(where: { $0.lowercased().contains(lowered) }) {
                results.append((meeting, "Tag", tag))
            }
        }
        return results
    }

    private func extractSnippet(from text: String, around query: String, contextChars: Int = 80) -> String {
        guard let range = text.lowercased().range(of: query) else { return String(text.prefix(contextChars)) }
        let center = text.distance(from: text.startIndex, to: range.lowerBound)
        let start = max(0, center - contextChars / 2)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(startIdx, offsetBy: min(contextChars, text.distance(from: startIdx, to: text.endIndex)))
        var snippet = String(text[startIdx ..< endIdx])
        if start > 0 {
            snippet = "..." + snippet
        }
        if endIdx < text.endIndex {
            snippet += "..."
        }
        return snippet
    }
}
