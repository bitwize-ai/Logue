import Foundation

/// What an approval card says is about to happen, and to what.
///
/// The card used to answer this with five hand-written sentences and a fallback of
/// "Agent wants to run \(toolName)". None of them named the thing being acted on, which is
/// the half that matters: every destructive tool here takes a **UUID**, so "Agent wants to
/// delete a document" is the whole of what the user was told before being asked for Touch ID.
/// Which document was not knowable from the card at all.
///
/// Pure, so the wording and the target extraction are testable without a view or a store. The
/// names themselves have to be looked up, which is what `resolve` is for — a caller on the
/// main actor asks the stores; a test passes a stub.
enum ToolApprovalPrompt {
    /// What kind of thing an id points at, so a caller knows which store to ask.
    enum TargetKind: Equatable {
        case document
        case space
        case reminder
        case calendarEvent
    }

    /// An id carried in the arguments, and what it points at.
    struct Reference: Equatable {
        let kind: TargetKind
        let id: UUID
    }

    /// Where the name of the thing being acted on comes from.
    private enum TargetSource {
        /// Nothing identifies a target — the action is the whole sentence.
        case none
        /// An argument holding a name, path, address or query, usable as written.
        case literal(String)
        /// An argument holding a UUID, which has to be resolved to something a person
        /// recognises before it is worth showing.
        case reference(TargetKind, String)
    }

    private struct Rule {
        let action: String
        let target: TargetSource
    }

    /// Longest target we will show. A path or a title can be arbitrarily long, and a prompt
    /// that wraps to five lines is one people stop reading — which is the failure mode an
    /// approval prompt can least afford.
    static let maxTargetLength = 64

    /// One entry per tool that can ask for approval.
    ///
    /// `ToolApprovalPromptTests` walks the registry and fails when a tool needing approval has
    /// no entry here, so adding a destructive tool without saying what it does is a red build
    /// rather than a card reading "Agent wants to run delete_everything".
    private static let rules: [String: Rule] = [
        // Documents
        "create_document": Rule(action: "Create a document", target: .literal("title")),
        "update_document": Rule(action: "Edit", target: .reference(.document, "documentID")),
        "delete_document": Rule(action: "Delete", target: .reference(.document, "documentID")),
        "move_document": Rule(action: "Move", target: .reference(.document, "documentID")),
        "add_document_tag": Rule(action: "Tag", target: .reference(.document, "documentID")),
        "export_document_pdf": Rule(action: "Export as PDF", target: .reference(.document, "documentID")),
        "create_document_from_template": Rule(action: "Create a document", target: .literal("title")),
        // Spaces
        "create_space": Rule(action: "Create a space", target: .literal("name")),
        "rename_space": Rule(action: "Rename", target: .reference(.space, "spaceID")),
        "delete_space": Rule(
            action: "Delete, with everything in it,",
            target: .reference(.space, "spaceID")
        ),
        // Calendar
        "create_calendar_event": Rule(action: "Create a calendar event", target: .literal("title")),
        "update_calendar_event": Rule(action: "Change", target: .reference(.calendarEvent, "eventID")),
        "delete_calendar_event": Rule(action: "Delete", target: .reference(.calendarEvent, "eventID")),
        // Reminders
        "add_reminder": Rule(action: "Add a reminder", target: .literal("title")),
        "update_reminder": Rule(action: "Change", target: .reference(.reminder, "reminderID")),
        "delete_reminder": Rule(action: "Delete", target: .reference(.reminder, "reminderID")),
        // The filesystem, where the path is the target and is already readable
        "list_directory": Rule(action: "List", target: .literal("path")),
        "read_file_at_path": Rule(action: "Read", target: .literal("path")),
        "write_text_to_file": Rule(action: "Write to", target: .literal("path")),
        "delete_file_at_path": Rule(action: "Delete the file", target: .literal("path")),
        // The user's own data, held by macOS rather than by Logue. Neither takes an id and
        // neither has a target worth naming — what matters is that the card says plainly
        // which private thing is about to be read, which "Agent wants to run get_location"
        // did not. Found by the coverage test below, not by hand.
        "fetch_contacts": Rule(action: "Read your contacts", target: .literal("name")),
        "get_location": Rule(action: "Read your current location", target: .none),
        // Off the machine
        "draft_email": Rule(action: "Draft an email to", target: .literal("to")),
        "web_search": Rule(action: "Search the web for", target: .literal("query")),
        "fetch_web_page": Rule(action: "Open", target: .literal("url")),
    ]

    /// Whether this tool has a prompt written for it.
    static func knows(toolNamed name: String) -> Bool {
        rules[name] != nil
    }

    /// The id this call will act on, if it acts on one that has to be looked up.
    static func reference(toolNamed name: String, arguments: String) -> Reference? {
        guard case let .reference(kind, key)? = rules[name]?.target,
              let raw = value(of: key, in: arguments),
              let id = UUID(uuidString: raw)
        else { return nil }
        return Reference(kind: kind, id: id)
    }

    /// The sentence to show above Approve and Reject.
    ///
    /// - Parameter resolve: turns a `Reference` into something a person recognises. Returning
    ///   `nil` — the object is gone, or the id was invented — leaves the action standing on
    ///   its own rather than showing a UUID, which tells the user nothing and looks like a
    ///   bug at the exact moment they are deciding whether to trust the agent.
    static func sentence(
        toolNamed name: String,
        arguments: String,
        resolve: (Reference) -> String?
    ) -> String {
        guard let rule = rules[name] else {
            // An unknown tool is still asking for permission, so say so plainly rather than
            // inventing a description of something we do not have a rule for.
            return "Run \(clamp(flatten(name)))"
        }

        let target: String? = switch rule.target {
        case .none:
            nil
        case let .literal(key):
            value(of: key, in: arguments).map { clamp(flatten($0)) }
        case .reference:
            reference(toolNamed: name, arguments: arguments)
                .flatMap(resolve)
                .map { clamp(flatten($0)) }
        }

        guard let target, !target.isEmpty else { return rule.action }
        return "\(rule.action) “\(target)”"
    }

    // MARK: - Reading arguments

    private static func value(of key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = dict[key]
        else { return nil }
        let string = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private static func flatten(_ value: String) -> String {
        DisplayText.singleLine(value)
    }

    private static func clamp(_ value: String) -> String {
        DisplayText.clamp(value, to: maxTargetLength)
    }
}
