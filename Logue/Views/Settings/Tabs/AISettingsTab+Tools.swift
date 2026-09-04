import SwiftUI

/// The per-tool switches, and the list of what can be switched.
///
/// Split out of `AISettingsTab` to keep its body inside the 450-line cap — the group list is
/// static data rather than logic, which is exactly the kind of thing the project's
/// extension-file rule exists to move. Nothing about the switches changed with the move.
///
/// Extension-visible: `toolsSection` is mounted by the tab's `body` in the core file.
extension AISettingsTab {
    static let toolGroups: [(title: String, items: [(String, String)])] = [
        ("Read — meetings & documents", [
            ("list_meetings", "Browse meetings"),
            ("search_meetings", "Keyword search meetings"),
            ("semantic_search_meetings", "Concept search meetings"),
            ("get_meeting_details", "Read a meeting"),
            ("get_transcript", "Read full transcript"),
            ("get_action_items", "Read action items"),
            ("get_daily_digest", "Daily activity digest"),
            ("list_documents", "Browse documents"),
            ("search_documents", "Keyword search documents"),
            ("semantic_search_documents", "Concept search documents"),
            ("get_document", "Read a document"),
        ]),
        ("Write — content", [
            ("create_document", "Create a document"),
            ("update_document", "Edit a document"),
            ("delete_document", "Delete a document"),
            ("move_document", "Move a document"),
            ("add_document_tag", "Tag a document"),
            ("create_space", "Create a space"),
            ("rename_space", "Rename a space"),
            ("delete_space", "Delete a space"),
            ("export_document_pdf", "Export a document as PDF"),
        ]),
        ("Calendar & Reminders", [
            ("get_upcoming_events", "List upcoming events"),
            ("create_calendar_event", "Create event"),
            ("update_calendar_event", "Update event"),
            ("delete_calendar_event", "Delete event"),
            ("get_reminders", "List reminders"),
            ("add_reminder", "Add reminder"),
            ("update_reminder", "Update reminder"),
            ("delete_reminder", "Delete reminder"),
        ]),
        ("AI helpers", [
            ("summarize_document", "Summarize"),
            ("rephrase_text", "Rephrase"),
            ("check_grammar", "Grammar check"),
            ("check_clarity", "Clarity check"),
            ("detect_tone", "Tone detect"),
            ("fact_check_document", "Fact-check"),
            ("detect_pii", "PII detect"),
            ("render_diagram", "Render diagram"),
            ("generate_slides", "Generate slide deck"),
        ]),
        ("Apple-native", [
            ("draft_email", "Draft email in Mail"),
            ("fetch_contacts", "Look up contacts"),
            ("get_location", "Get current location"),
        ]),
        ("Compute & dialogs", [
            ("run_javascript", "Run JavaScript"),
            ("get_confirmation", "Yes/no dialog"),
            ("get_text_input", "Text input dialog"),
            ("get_user_selection", "Pick-one dialog"),
        ]),
        ("Files (Phase G)", [
            ("list_directory", "List directory contents"),
            ("read_file_at_path", "Read file at path"),
            ("write_text_to_file", "Write text to file"),
            ("delete_file_at_path", "Delete file at path"),
        ]),
    ]

    var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tools", subtitle: "Turn off any tool you don't want the agent to call. Toggling takes effect on the next message.")
            ForEach(Self.toolGroups, id: \.title) { group in
                DisclosureGroup(group.title) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(group.items, id: \.0) { item in
                            toolRow(name: item.0, label: item.1)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
                .font(.callout.weight(.medium))
            }
        }
    }

    private func toolRow(name: String, label: String) -> some View {
        let isEnabled = !disabledTools.contains(name)
        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in setTool(name, enabled: newValue) }
        )) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.switch)
    }

    private func setTool(_ name: String, enabled: Bool) {
        var current = disabledTools
        if enabled {
            current.remove(name)
        } else {
            current.insert(name)
        }
        disabledToolsRaw = current.sorted().joined(separator: ",")
    }
}
