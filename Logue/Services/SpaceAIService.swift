import Foundation
import os.log

/// Provides AI-powered commands that operate on an entire Space's contents.
/// Aggregates meetings and documents within a Space (and descendants) to generate
/// cross-item summaries, action-item rollups, and status updates.
@MainActor
enum SpaceAIService {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "SpaceAIService")

    // MARK: - Space Summary

    /// Generates a high-level summary across all meetings and documents in a Space.
    static func summarizeSpace(spaceID: UUID) async throws -> String {
        let context = buildSpaceContext(spaceID: spaceID)
        guard !context.isEmpty else {
            let empty = "This space has no content to summarize."
            persistInsight(spaceID: spaceID, key: "summary", content: empty)
            return empty
        }

        let prompt = """
        Summarize this workspace's contents in 3-5 paragraphs.

        ---

        <workspace>
        \(context)
        </workspace>
        """

        let result = try await withRetry {
            let result = try await LLMEngine.shared.complete(
                system: PromptRegistry.Space.summarySystem.content,
                prompt: prompt,
                maxTokens: 1024
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyResponse
            }
            return result
        }
        persistInsight(spaceID: spaceID, key: "summary", content: result)
        return result
    }

    // MARK: - Open Action Items

    /// Aggregates all action items from meetings within a Space.
    static func aggregateActionItems(spaceID: UUID) async throws -> String {
        let store = MeetingStore.shared
        let spaceStore = SpaceStore.shared
        let allSpaceIDs = spaceStore.allDescendantIDs(of: spaceID).union([spaceID])

        var allActionItems: [(meetingTitle: String, items: [String])] = []
        for meeting in store.activeMeetings {
            guard let sid = meeting.spaceID, allSpaceIDs.contains(sid) else { continue }
            let items: [String]
            if !meeting.actionItems.isEmpty {
                items = meeting.actionItems.map(\.title)
            } else if let sm = meeting.smartMinutes, !sm.actionItems.isEmpty {
                items = sm.actionItems
            } else {
                continue
            }
            allActionItems.append((meetingTitle: meeting.title, items: items))
        }

        guard !allActionItems.isEmpty else {
            let empty = "No action items found in this space."
            persistInsight(spaceID: spaceID, key: "actionItems", content: empty)
            return empty
        }

        // Build a structured list without needing LLM
        var result = "## Action Items\n\n"
        for group in allActionItems {
            result += "### From: \(group.meetingTitle)\n"
            for item in group.items {
                result += "- [ ] \(item)\n"
            }
            result += "\n"
        }

        persistInsight(spaceID: spaceID, key: "actionItems", content: result)
        return result
    }

    // MARK: - Status Update

    /// Generates a project status update document from all Space contents.
    static func generateStatusUpdate(spaceID: UUID) async throws -> String {
        let context = buildSpaceContext(spaceID: spaceID)
        guard !context.isEmpty else {
            let empty = "This space has no content to generate a status update from."
            persistInsight(spaceID: spaceID, key: "statusUpdate", content: empty)
            return empty
        }

        let prompt = """
        Generate a status update for this workspace.

        ---

        <workspace>
        \(context)
        </workspace>
        """

        let result = try await withRetry {
            let result = try await LLMEngine.shared.complete(
                system: PromptRegistry.Space.statusUpdateSystem.content,
                prompt: prompt,
                maxTokens: 1024
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyResponse
            }
            return result
        }
        persistInsight(spaceID: spaceID, key: "statusUpdate", content: result)
        return result
    }

    // MARK: - What Was Decided

    /// Extracts all decisions from meetings within a Space.
    static func extractDecisions(spaceID: UUID) async throws -> String {
        let store = MeetingStore.shared
        let spaceStore = SpaceStore.shared
        let allSpaceIDs = spaceStore.allDescendantIDs(of: spaceID).union([spaceID])

        var decisions: [(meetingTitle: String, date: Date, items: [String])] = []
        for meeting in store.activeMeetings {
            guard let sid = meeting.spaceID, allSpaceIDs.contains(sid) else { continue }
            if let sm = meeting.smartMinutes, !sm.keyDecisions.isEmpty {
                decisions.append((meetingTitle: meeting.title, date: meeting.createdAt, items: sm.keyDecisions))
            }
        }

        guard !decisions.isEmpty else {
            let empty = "No recorded decisions found in this space."
            persistInsight(spaceID: spaceID, key: "decisions", content: empty)
            return empty
        }

        var result = "## Decisions\n\n"
        for group in decisions.sorted(by: { $0.date > $1.date }) {
            let dateStr = group.date.formatted(date: .abbreviated, time: .omitted)
            result += "### \(group.meetingTitle) (\(dateStr))\n"
            for decision in group.items {
                result += "- \(decision)\n"
            }
            result += "\n"
        }

        persistInsight(spaceID: spaceID, key: "decisions", content: result)
        return result
    }

    // MARK: - Persistence Helper

    private static func persistInsight(spaceID: UUID, key: String, content: String) {
        let signature = SpaceStore.contentSignature(
            spaceID: spaceID,
            spaceStore: .shared,
            documentStore: .shared,
            meetingStore: .shared
        )
        SpaceStore.shared.setAIInsight(
            id: spaceID,
            key: key,
            content: content,
            contentSignature: signature
        )
    }

    // MARK: - Context Builder

    /// Builds a text context from all items in a Space (including descendants).
    private static func buildSpaceContext(spaceID: UUID) -> String {
        let docStore = DocumentStore.shared
        let meetingStore = MeetingStore.shared
        let spaceStore = SpaceStore.shared
        let allSpaceIDs = spaceStore.allDescendantIDs(of: spaceID).union([spaceID])

        var sections: [String] = []

        // Meetings with summaries
        for meeting in meetingStore.activeMeetings {
            guard let sid = meeting.spaceID, allSpaceIDs.contains(sid) else { continue }
            let sanitizedTitle = String(meeting.title.prefix(100)).filter { !$0.isNewline && $0.asciiValue != 0 }
            var section = "MEETING: \(sanitizedTitle) (\(meeting.createdAt.formatted(date: .abbreviated, time: .omitted)))\n"
            if let summary = meeting.summary {
                section += "Summary: \(String(summary.prefix(500)))\n"
            }
            if let sm = meeting.smartMinutes {
                if !sm.keyDecisions.isEmpty {
                    section += "Decisions: \(sm.keyDecisions.joined(separator: "; "))\n"
                }
                if !sm.actionItems.isEmpty {
                    section += "Action Items: \(sm.actionItems.joined(separator: "; "))\n"
                }
                if !sm.discussionPoints.isEmpty {
                    section += "Discussion: \(sm.discussionPoints.prefix(5).joined(separator: "; "))\n"
                }
            }
            if !meeting.topicKeywords.isEmpty {
                section += "Topics: \(meeting.topicKeywords.joined(separator: ", "))\n"
            }
            sections.append(section)
        }

        // Documents
        for doc in docStore.activeDocuments {
            guard let sid = doc.spaceID, allSpaceIDs.contains(sid) else { continue }
            let sanitizedDocTitle = String(doc.title.prefix(100)).filter { !$0.isNewline && $0.asciiValue != 0 }
            var section = "DOCUMENT: \(sanitizedDocTitle) (\(doc.modifiedAt.formatted(date: .abbreviated, time: .omitted)))\n"
            let body = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                section += "Content: \(String(body.prefix(400)))\n"
            }
            sections.append(section)
        }

        // Limit total context to avoid exceeding model capacity — adapts to model's context window
        let joined = sections.joined(separator: "\n---\n")
        let maxChars = LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens)
        return String(joined.prefix(maxChars))
    }
}
