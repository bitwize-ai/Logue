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
        /// An argument holding a name, address or query, usable as written.
        case literal(String)
        /// An argument holding a filesystem path, where the end is the part that matters.
        case path(String)
        /// An argument holding a web address, where the host is the part that matters.
        case url(String)
        /// An argument holding a UUID, which has to be resolved to something a person
        /// recognises before it is worth showing.
        case reference(TargetKind, String)
    }

    private struct Rule {
        /// What is said in front of the target: `Delete “Q3 Planning”`.
        let action: String
        /// The whole sentence when there is no target to name.
        ///
        /// Never a bare verb. A reminder or calendar event cannot be named at all, and a
        /// document whose id does not resolve cannot either — and "Delete" above Approve says
        /// less than the tool name it replaced. So the kind of thing is always stated.
        let alone: String
        let target: TargetSource

        init(_ action: String, alone: String? = nil, target: TargetSource) {
            self.action = action
            self.alone = alone ?? action
            self.target = target
        }
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
        "create_document": Rule("Create a document", target: .literal("title")),
        "update_document": Rule("Edit", alone: "Edit a document", target: .reference(.document, "documentID")),
        "delete_document": Rule("Delete", alone: "Delete a document", target: .reference(.document, "documentID")),
        "move_document": Rule("Move", alone: "Move a document", target: .reference(.document, "documentID")),
        "add_document_tag": Rule("Tag", alone: "Tag a document", target: .reference(.document, "documentID")),
        "export_document_pdf": Rule(
            "Export as PDF",
            alone: "Export a document as PDF",
            target: .reference(.document, "documentID")
        ),
        "create_document_from_template": Rule("Create a document", target: .literal("title")),
        // Spaces
        "create_space": Rule("Create a space", target: .literal("name")),
        "rename_space": Rule("Rename", alone: "Rename a space", target: .reference(.space, "spaceID")),
        "delete_space": Rule(
            "Delete, with everything in it,",
            alone: "Delete a space, with everything in it",
            target: .reference(.space, "spaceID")
        ),
        // Calendar and reminders. Changing or deleting one takes an EventKit id, which
        // `ToolApprovalTargetResolver` does not look up, so those four are only ever shown
        // in their `alone` form.
        "create_calendar_event": Rule("Create a calendar event", target: .literal("title")),
        "update_calendar_event": Rule(
            "Change",
            alone: "Change a calendar event",
            target: .reference(.calendarEvent, "eventID")
        ),
        "delete_calendar_event": Rule(
            "Delete",
            alone: "Delete a calendar event",
            target: .reference(.calendarEvent, "eventID")
        ),
        "add_reminder": Rule("Add a reminder", target: .literal("title")),
        "update_reminder": Rule("Change", alone: "Change a reminder", target: .reference(.reminder, "reminderID")),
        "delete_reminder": Rule("Delete", alone: "Delete a reminder", target: .reference(.reminder, "reminderID")),
        // The filesystem, where the path is the target and is already readable
        "list_directory": Rule("List", alone: "List a folder", target: .path("path")),
        "read_file_at_path": Rule("Read", alone: "Read a file", target: .path("path")),
        "write_text_to_file": Rule("Write to", alone: "Write to a file", target: .path("path")),
        "delete_file_at_path": Rule("Delete the file", alone: "Delete a file", target: .path("path")),
        // The user's own data, held by macOS rather than by Logue. Neither takes an id; what
        // matters is that the card says plainly which private thing is about to be read,
        // which "Agent wants to run get_location" did not. Contacts can be narrowed by name,
        // so that is shown when given. Found by `everyGatedToolHasAPrompt`, not by hand.
        "fetch_contacts": Rule("Read your contacts matching", alone: "Read your contacts", target: .literal("name")),
        "get_location": Rule("Read your current location", target: .none),
        // Off the machine
        "draft_email": Rule("Draft an email to", alone: "Draft an email", target: .literal("to")),
        "web_search": Rule("Search the web for", alone: "Search the web", target: .literal("query")),
        "fetch_web_page": Rule("Open", alone: "Open a web page", target: .url("url")),
    ]

    /// Whether this tool has a prompt written for it. Asked by the coverage test, which is
    /// what keeps `rules` in step with the registry.
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
    ///   `nil` — the object is gone, or the id was invented — gives the rule's sentence
    ///   without a name rather than showing a UUID, which tells the user nothing and looks
    ///   like a bug at the exact moment they are deciding whether to trust the agent.
    static func sentence(
        toolNamed name: String,
        arguments: String,
        resolve: (Reference) -> String?
    ) -> String {
        guard let rule = rules[name] else {
            // An unknown tool is still asking for permission, so say so plainly rather than
            // inventing a description of something we do not have a rule for.
            return "Run \(DisplayText.clamp(DisplayText.singleLine(name), to: maxTargetLength))"
        }

        let target: String? = switch rule.target {
        case .none:
            nil
        case let .literal(key):
            line(key, in: arguments).map { DisplayText.clamp($0, to: maxTargetLength) }
        case let .path(key):
            line(key, in: arguments).map { DisplayText.clampMiddle($0, to: maxTargetLength) }
        case let .url(key):
            // Not trimmed: the tool is handed the argument whole, and trailing whitespace
            // is sent, encoded, as part of the address.
            (ToolArgumentSummary.dictionary(fromJSON: arguments)?[key] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                .map(webAddress)
        case .reference:
            reference(toolNamed: name, arguments: arguments)
                .flatMap(resolve)
                .map { DisplayText.clamp(DisplayText.singleLine($0), to: maxTargetLength) }
        }

        guard let target, !target.isEmpty else { return rule.alone }
        return "\(rule.action) “\(target)”"
    }

    /// A web address, host first and never cut from its end.
    ///
    /// The host is what says where a request is going, and it is easy to bury: cut from the
    /// tail, `accounts.example.com.<padding>.elsewhere.tld` shows only its reassuring start.
    /// So it is taken out by parsing rather than by position — which also sees through
    /// `https://trusted.example@elsewhere.tld` — and whatever room is left goes to the rest.
    ///
    /// Parsed from the argument **as given**, before any scrubbing: a character deleted first
    /// is one the request still sends, percent-encoded, so the card would show less than
    /// leaves the machine. Each part is then shown the way it is used:
    ///
    /// - The host as `shownHost` decides, which is the one part where neither form is always
    ///   the honest one.
    /// - The path and query still encoded, so `%0A` or `%E2%80%AE` cannot arrive as a newline
    ///   or a bidirectional override. The query keeps a share of the room however long the
    ///   path is, down to a bare `?…`: it is where a request carries data out.
    ///
    /// User-info is not shown because `FetchWebPageTool` refuses an address that carries any.
    private static func webAddress(_ value: String) -> String {
        guard let parts = URLComponents(string: value),
              let encodedHost = parts.encodedHost, !encodedHost.isEmpty
        else {
            return DisplayText.clampMiddle(DisplayText.singleLine(value), to: maxTargetLength)
        }
        let host = shownHost(encodedHost)
        let authority = parts.port.map { "\(host):\($0)" } ?? host

        let path = DisplayText.singleLine(parts.percentEncodedPath == "/" ? "" : parts.percentEncodedPath)
        let query = parts.percentEncodedQuery.map { DisplayText.singleLine("?\($0)") } ?? ""
        guard !path.isEmpty || !query.isEmpty else {
            return DisplayText.clampStart(authority, to: maxTargetLength)
        }

        // Room for at least the mark that says something follows the host: `…`, or `?…`.
        let leastTail = query.isEmpty ? 1 : 2
        let shownAuthority = DisplayText.clampStart(authority, to: maxTargetLength - leastTail)
        let room = maxTargetLength - shownAuthority.count
        guard !query.isEmpty else {
            return shownAuthority + (room > 1 ? DisplayText.clamp(path, to: room) : "…")
        }

        let pathRoom = room - min(query.count, max(2, room / 3))
        // A path cut to a single character would be its leading slash — a root path, where
        // there is a longer one. Mark it instead, or leave it out when there is no room.
        let shownPath = if path.count <= pathRoom {
            path
        } else if pathRoom > 1 {
            DisplayText.clamp(path, to: pathRoom)
        } else {
            pathRoom == 1 ? "…" : ""
        }
        return shownAuthority + shownPath + DisplayText.clamp(query, to: room - shownPath.count)
    }

    /// The host, with a percent-escape resolved only when it stands for a hostname character.
    ///
    /// The connection resolves escapes, so `good.example%2Eelsewhere.tld` is a request to
    /// `good.example.elsewhere.tld` and showing the hex would hide where it goes. But most
    /// things an escape can stand for make the card lie once resolved: a `/`, `?` or `:`
    /// reads as the *end* of the host, a letter from another script reads as the name it
    /// imitates, and an invisible character reads as nothing at all. There are too many of
    /// those to list, so the rule runs the other way — a letter, a digit, a hyphen or a dot
    /// in ASCII is resolved, and every other escape stays as hex: ugly, and accurate.
    /// Decided escape by escape, so a hidden dot is revealed even beside one that is not.
    private static func shownHost(_ encodedHost: String) -> String {
        var shown = ""
        var rest = Substring(encodedHost)
        while let percent = rest.firstIndex(of: "%") {
            shown += rest[..<percent]
            let escape = rest[percent...].prefix(3)
            if escape.count == 3,
               let byte = UInt8(escape.dropFirst(), radix: 16),
               isHostnameCharacter(byte)
            {
                shown.append(Character(Unicode.Scalar(byte)))
            } else {
                shown += escape
            }
            rest = rest[percent...].dropFirst(escape.count)
        }
        return DisplayText.singleLine(shown + rest)
    }

    private static func isHostnameCharacter(_ byte: UInt8) -> Bool {
        let scalar = Unicode.Scalar(byte)
        guard scalar.isASCII else { return false }
        return scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) || scalar == "-" || scalar == "."
    }

    // MARK: - Reading arguments

    private static func value(of key: String, in json: String) -> String? {
        guard let raw = ToolArgumentSummary.dictionary(fromJSON: json)?[key], !(raw is NSNull) else { return nil }
        let string = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    /// An argument as one safe line, or `nil` when it is absent or scrubs away to nothing.
    private static func line(_ key: String, in json: String) -> String? {
        guard let raw = value(of: key, in: json) else { return nil }
        let flattened = DisplayText.singleLine(raw)
        return flattened.isEmpty ? nil : flattened
    }
}
