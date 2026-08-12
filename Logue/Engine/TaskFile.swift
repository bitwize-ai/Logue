import Foundation

/// The plain-markdown storage format for a task.
///
/// Mirrors `MarkdownDocumentFile`, and for the same reason: in markdown mode the file
/// **is** the task, so round-trip fidelity is the whole contract. Key order is fixed and
/// lists are emitted in a stable order, because these files may be tracked in git and
/// unstable output would mean a diff on every save.
///
/// Reading is deliberately tolerant — an unrecognised key is ignored, a malformed date or
/// enum falls back rather than failing the whole read — because these files are meant to
/// be hand-edited. The one strict requirement is the identifier: without it the file is
/// not a known task, and inventing one risks attaching it to the wrong record.
enum TaskFile {
    /// Frontmatter key holding the task identifier.
    ///
    /// Underscore-prefixed to mark it app-owned: `PropertyKey.sanitisedKey` refuses such
    /// names, so a user cannot create a property that collides with it.
    static let identifierKey = "_logue_task_id"

    /// The folder tasks live in, under the markdown root.
    static let folderName = "Tasks"

    /// The marker that gives the tasks folder an identity.
    ///
    /// Named and shaped after `_space.md` deliberately: a folder is found by its identity,
    /// never by recomputing a path from its name. Renaming `Tasks/` in Finder must keep
    /// tasks working *and* keep them out of the document library.
    static let folderMarkerFilename = "_tasks.md"
    static let folderMarkerKey = "_logue_tasks_folder"

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Writing

    static func render(_ task: TaskItem) -> String {
        var fields: [(key: String, value: FrontmatterValue)] = [
            (identifierKey, .scalar(task.id.uuidString)),
            ("title", .scalar(task.title)),
            ("status", .scalar(task.status.rawValue)),
            ("priority", .scalar(task.priority.rawValue)),
        ]

        if let dueDate = task.dueDate {
            fields.append(("due", .scalar(dayFormatter.string(from: dueDate))))
        }
        if !task.tags.isEmpty {
            fields.append(("tags", .list(task.tags)))
        }
        if let spaceID = task.spaceID {
            fields.append(("space", .scalar(spaceID.uuidString)))
        }
        if let recurrence = task.recurrence {
            fields.append(("recur", .scalar(recurrence.storageString)))
        }
        fields.append(("created", .scalar(isoFormatter.string(from: task.createdAt))))
        fields.append(("updated", .scalar(isoFormatter.string(from: task.updatedAt))))
        if task.completedCount > 0 {
            fields.append(("completed_count", .scalar(String(task.completedCount))))
        }
        if let meetingID = task.sourceMeetingID {
            fields.append(("meeting", .scalar(meetingID.uuidString)))
        }

        let body = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownFrontmatter.render(fields) + "\n" + body + (body.isEmpty ? "" : "\n")
    }

    // MARK: - Reading

    static func parse(_ markdown: String) -> TaskItem? {
        let (fields, body) = MarkdownFrontmatter.parse(markdown)

        guard case let .scalar(rawID)? = fields[identifierKey], let id = UUID(uuidString: rawID) else {
            return nil
        }

        var task = TaskItem(id: id)
        task.title = scalar(fields, "title") ?? "Untitled task"
        // A malformed enum falls back rather than failing the read: losing a priority costs
        // a badge, refusing the file costs the user their task.
        task.status = TaskStatus(rawValue: scalar(fields, "status") ?? "") ?? .todo
        task.priority = TaskPriority(rawValue: scalar(fields, "priority") ?? "") ?? .medium
        task.dueDate = scalar(fields, "due").flatMap { dayFormatter.date(from: $0) }
        task.spaceID = scalar(fields, "space").flatMap(UUID.init(uuidString:))
        task.recurrence = scalar(fields, "recur").flatMap(TaskRecurrence.parse)
        task.createdAt = scalar(fields, "created").flatMap { isoFormatter.date(from: $0) } ?? .now
        task.updatedAt = scalar(fields, "updated").flatMap { isoFormatter.date(from: $0) } ?? task.createdAt
        task.completedCount = scalar(fields, "completed_count").flatMap(Int.init) ?? 0
        task.sourceMeetingID = scalar(fields, "meeting").flatMap(UUID.init(uuidString:))
        task.notes = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if case let .list(tags)? = fields["tags"] {
            task.tags = tags
        } else if let single = scalar(fields, "tags") {
            task.tags = [single]
        }

        return task
    }

    private static func scalar(_ fields: [String: FrontmatterValue], _ key: String) -> String? {
        guard case let .scalar(value)? = fields[key], !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Filenames

    /// Reuses the document rule, which is the path-safety boundary — nothing derived from a
    /// user-controlled title may contain a separator or escape the folder.
    static func filename(for task: TaskItem, avoiding taken: Set<String> = []) -> String {
        DocumentFilename.filename(forTitle: task.title, id: task.id, avoiding: taken)
    }

    // MARK: - Folder marker

    static func folderMarkerContents(id: UUID) -> String {
        MarkdownFrontmatter.render([(folderMarkerKey, .scalar(id.uuidString))])
            + """

            This folder holds your tasks, one Markdown file each. Edit them in any editor —
            Logue reads them back. Do not remove this file: it is how Logue recognises the
            folder, so that renaming the folder keeps working.

            """
    }

    static func isFolderMarker(filename: String) -> Bool {
        filename.caseInsensitiveCompare(folderMarkerFilename) == .orderedSame
    }

    /// The identity inside a marker file, or `nil` when the contents are not one.
    static func markerIdentifier(in contents: String) -> UUID? {
        guard case let .scalar(raw)? = MarkdownFrontmatter.parse(contents).fields[folderMarkerKey] else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    /// Whether a file's contents claim to be a task — a second check, in case it was renamed.
    static func isTaskFile(contents: String) -> Bool {
        MarkdownFrontmatter.parse(contents).fields[identifierKey] != nil
    }
}
