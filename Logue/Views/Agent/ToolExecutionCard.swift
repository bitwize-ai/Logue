import SwiftUI

/// Claude-style inline tool execution indicator.
///
/// Collapsed: single line with icon + description + status (e.g. "Searched 5 meetings")
/// Expanded: shows tool name, arguments, and formatted result content.
/// Approval state: shows Approve / Reject buttons for destructive tools pending confirmation.
struct ToolExecutionCard: View {
    let toolCall: AgentToolCall
    let result: AgentToolResult?
    /// Conversation ID — required only when the card may render approval buttons; nil for
    /// non-destructive cards rendered from history.
    let conversationID: UUID?

    @State private var isExpanded = false

    init(toolCall: AgentToolCall, result: AgentToolResult?, conversationID: UUID? = nil) {
        self.toolCall = toolCall
        self.result = result
        self.conversationID = conversationID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed: single-line summary row
            Button {
                guard result != nil else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // Expand chevron (only if result available)
                    if result != nil {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                    }

                    // Tool icon
                    toolIcon
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)

                    // Summary text
                    Text(summaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Approval buttons (destructive + awaiting confirmation)
                    if toolCall.status == .needsConfirmation, let conversationID {
                        ToolApprovalButtons(
                            toolCallID: toolCall.id,
                            conversationID: conversationID,
                            clearance: toolCall.clearance
                        )
                    } else {
                        statusBadge
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: tool details + result
            if isExpanded, let result {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 8)

                    // Tool name + arguments
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(toolCall.toolName)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)

                            if !toolCall.arguments.isEmpty, toolCall.arguments != "{}" {
                                Text(formatArguments(toolCall.arguments))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        // Result content
                        MarkdownTextView(text: result.output)
                            .font(.caption)
                            .foregroundStyle(result.isError ? .red : .primary)

                        // Phase C polish: when the result references a rendered
                        // diagram, embed the SVG inline below the tool card.
                        if toolCall.toolName == "render_diagram", !result.isError {
                            InlineDiagramView(messageContent: result.output)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary Text

    /// Human-readable one-line summary of what the tool did.
    private var summaryText: String {
        if toolCall.status == .needsConfirmation {
            return pendingApprovalText
        }
        guard let result, !result.isError else {
            if toolCall.status == .running || toolCall.status == .pending {
                return runningText
            }
            return "Failed to \(actionVerb)"
        }
        return completedSummary(from: result.output)
    }

    private var pendingApprovalText: String {
        switch toolCall.toolName {
        case "update_document": "Agent wants to update a document"
        case "delete_document": "Agent wants to delete a document"
        case "rename_space": "Agent wants to rename a space"
        case "delete_space": "Agent wants to delete a space"
        case "create_calendar_event": "Agent wants to create a calendar event"
        default: "Agent wants to run \(toolCall.toolName)"
        }
    }

    private var runningText: String {
        switch toolCall.toolName {
        case "search_meetings": "Searching meetings..."
        case "list_meetings": "Loading meetings..."
        case "get_meeting_details": "Loading meeting details..."
        case "get_transcript": "Loading transcript..."
        case "get_action_items": "Loading action items..."
        case "get_daily_digest": "Generating daily digest..."
        case "list_documents": "Loading documents..."
        case "search_documents": "Searching documents..."
        case "get_document": "Loading document..."
        case "get_upcoming_events": "Checking calendar..."
        case "create_document": "Creating document..."
        case "update_document": "Updating document..."
        case "delete_document": "Deleting document..."
        case "move_document": "Moving document..."
        case "add_document_tag": "Adding tag..."
        case "create_space": "Creating space..."
        case "rename_space": "Renaming space..."
        case "delete_space": "Deleting space..."
        case "create_calendar_event": "Creating calendar event..."
        case "summarize_document": "Summarizing document..."
        case "rephrase_text": "Rephrasing text..."
        case "check_grammar": "Checking grammar..."
        case "check_clarity": "Checking clarity..."
        case "detect_tone": "Detecting tone..."
        case "fact_check_document": "Fact-checking document..."
        case "detect_pii": "Scanning for PII..."
        case "list_templates": "Loading templates..."
        case "create_document_from_template": "Creating from template..."
        case "export_document_pdf": "Exporting PDF..."
        default: "Running \(toolCall.toolName)..."
        }
    }

    // swiftlint:disable cyclomatic_complexity
    private func completedSummary(from output: String) -> String {
        let firstLine = output.components(separatedBy: "\n").first ?? output
        let count = extractCount(from: firstLine)

        switch toolCall.toolName {
        // Read-only meetings
        case "search_meetings":
            if output.starts(with: "No meetings") {
                return "No matching meetings found"
            }
            return count.map { "Found \($0) matching meeting\($0 == 1 ? "" : "s")" } ?? "Searched meetings"
        case "list_meetings":
            return count.map { "Loaded \($0) meeting\($0 == 1 ? "" : "s")" } ?? "Listed meetings"
        case "get_meeting_details":
            return "Loaded meeting details"
        case "get_transcript":
            return "Loaded transcript"
        case "get_action_items":
            if output.starts(with: "No") {
                return "No action items found"
            }
            return count.map { "Found \($0) action item\($0 == 1 ? "" : "s")" } ?? "Loaded action items"
        case "get_daily_digest":
            if output.contains("No meetings") {
                return "No meetings today"
            }
            return count.map { "Summarized \($0) meeting\($0 == 1 ? "" : "s")" } ?? "Generated daily digest"
        // Read-only documents
        case "list_documents":
            if output.starts(with: "No") {
                return "No documents found"
            }
            return count.map { "Loaded \($0) document\($0 == 1 ? "" : "s")" } ?? "Listed documents"
        case "search_documents":
            if output.starts(with: "No documents") {
                return "No matching documents found"
            }
            return count.map { "Found \($0) matching document\($0 == 1 ? "" : "s")" } ?? "Searched documents"
        case "get_document":
            return "Loaded document content"
        // Read-only calendar
        case "get_upcoming_events":
            if output.contains("No upcoming") || output.contains("not enabled") {
                return "No upcoming events"
            }
            return count.map { "Found \($0) upcoming event\($0 == 1 ? "" : "s")" } ?? "Checked calendar"
        // Templates & export
        case "list_templates":
            return count.map { "Loaded \($0) template\($0 == 1 ? "" : "s")" } ?? "Listed templates"
        case "create_document_from_template": return "Created document from template"
        case "export_document_pdf": return "Exported PDF"
        default:
            return writeOrAISummary()
        }
    }

    // swiftlint:enable cyclomatic_complexity

    /// Summaries for write and AI tools — plain, count-independent labels.
    private func writeOrAISummary() -> String {
        let summaries: [String: String] = [
            // Writes
            "create_document": "Created document",
            "update_document": "Updated document",
            "delete_document": "Moved document to trash",
            "move_document": "Moved document",
            "add_document_tag": "Added tag",
            "create_space": "Created space",
            "rename_space": "Renamed space",
            "delete_space": "Deleted space",
            "create_calendar_event": "Created calendar event",
            // AI
            "summarize_document": "Summarized document",
            "rephrase_text": "Rephrased text",
            "check_grammar": "Checked grammar",
            "check_clarity": "Checked clarity",
            "detect_tone": "Detected tone",
            "fact_check_document": "Fact-checked document",
            "detect_pii": "Scanned for PII",
        ]
        return summaries[toolCall.toolName] ?? "Executed \(toolCall.toolName)"
    }

    /// Extracts the first number from a string (e.g. "Found 5 meeting(s)" → 5).
    private func extractCount(from text: String) -> Int? {
        let digits = text.components(separatedBy: .decimalDigits.inverted).compactMap { Int($0) }
        return digits.first
    }

    private var actionVerb: String {
        switch toolCall.toolName {
        case "search_meetings", "search_documents": "search"
        case "list_meetings", "list_documents": "load list"
        case "get_action_items": "load action items"
        case "get_daily_digest": "generate digest"
        case "get_upcoming_events": "check calendar"
        default: "execute"
        }
    }

    // MARK: - Icons & Status

    @ViewBuilder
    private var toolIcon: some View {
        switch toolCall.toolName {
        case let name where name.contains("meeting"), let name where name.contains("transcript"):
            Image(systemName: "mic.fill")
        case let name where name.contains("document") || name.contains("rephrase"):
            Image(systemName: "doc.text.fill")
        case let name where name.contains("template"):
            Image(systemName: "doc.on.doc.fill")
        case let name where name.contains("calendar") || name.contains("event"):
            Image(systemName: "calendar")
        case let name where name.contains("space"):
            Image(systemName: "folder.fill")
        case let name where name.contains("action"):
            Image(systemName: "checklist")
        case let name where name.contains("digest"):
            Image(systemName: "newspaper.fill")
        case let name where name.contains("grammar") || name.contains("clarity") || name.contains("tone"):
            Image(systemName: "text.magnifyingglass")
        case let name where name.contains("fact_check"):
            Image(systemName: "checkmark.seal")
        case let name where name.contains("pii"):
            Image(systemName: "lock.shield.fill")
        case let name where name.contains("export") || name.contains("pdf"):
            Image(systemName: "square.and.arrow.up")
        case let name where name.contains("summar"):
            Image(systemName: "text.redaction")
        default:
            Image(systemName: "wrench.fill")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch toolCall.status {
        case .pending, .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
        case .needsConfirmation:
            Image(systemName: "questionmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
        }
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .completed: .green
        case .failed: .red
        case .needsConfirmation: .orange
        default: .secondary
        }
    }

    // MARK: - Helpers

    private func formatArguments(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        return dict.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}
