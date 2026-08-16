import SwiftUI

/// Everything about one task, editable.
///
/// Exists because capture used to be the only moment a task could be described: a typo in a
/// title, or a deadline that moved, meant deleting and retyping — which also threw away the
/// meeting a promoted task came from. The AI triage panel could already set a due date and a
/// tag, so until now the model could edit a task and its owner could not.
///
/// Free text commits when it loses focus rather than on every keystroke: in plain-markdown
/// mode each change rewrites the task's `.md` file, and a write per character would be one
/// filesystem event per character.
struct TaskInspectorPanel: View {
    let task: TaskItem
    let meetingTitle: String?
    let onChange: (TaskItem) -> Void
    let onDelete: () -> Void
    let onOpenSource: () -> Void
    let onClose: () -> Void

    /// Fixed width for now. `LibraryPanelContainer` is what this would reuse to become
    /// resizable; it is not wired up here yet.
    private let panelWidth: CGFloat = 320

    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var newTag = ""
    /// The task the drafts were loaded from. Held whole rather than by id so a commit can be
    /// built from it after `task` has already moved on to another row.
    @State private var draftSource: TaskItem?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title
        case notes
        case tag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleSection
                    dueDateSection
                    prioritySection
                    tagsSection
                    recurrenceSection
                    notesSection
                    sourceSection
                    deleteButton
                }
                .padding(16)
            }
        }
        .frame(width: panelWidth)
        .background(AppThemeConstants.surfaceBackground)
        .onAppear(perform: loadDrafts)
        // Switching rows commits the outgoing row's text to the outgoing row, then loads
        // the new one. `commitDrafts` writes to `draftSource`, so nothing can land on the
        // task that just became selected.
        .onChange(of: task.id) {
            commitDrafts()
            loadDrafts()
        }
        .onChange(of: focus) { previous, _ in
            if previous != nil {
                commitDrafts()
            }
        }
        .onDisappear(perform: commitDrafts)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Task")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
            .accessibilityLabel("Close task details")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Title

    private var titleSection: some View {
        section("Title") {
            TextField("Title", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .focused($focus, equals: .title)
                .onSubmit(commitDrafts)
                .padding(8)
                .background(
                    AppThemeConstants.textInputBackground,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                )
        }
    }

    // MARK: - Due date

    private var dueDateSection: some View {
        section("Due") {
            if let due = task.dueDate {
                HStack {
                    DatePicker(
                        "Due",
                        selection: Binding(
                            get: { due },
                            set: { newValue in
                                var updated = task
                                // Day precision, held at the start of its day — the model's
                                // rule, so "overdue" does not depend on the hour it was set.
                                updated.dueDate = Calendar.current.startOfDay(for: newValue)
                                onChange(updated)
                            }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()

                    Button("Clear") {
                        var updated = task
                        updated.dueDate = nil
                        onChange(updated)
                    }
                    .buttonStyle(.link)
                }
            } else {
                Button("Add a due date") {
                    var updated = task
                    updated.dueDate = Calendar.current.startOfDay(for: .now)
                    onChange(updated)
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Priority

    private var prioritySection: some View {
        section("Priority") {
            Picker("Priority", selection: Binding(
                get: { task.priority },
                set: { newValue in
                    var updated = task
                    updated.priority = newValue
                    onChange(updated)
                }
            )) {
                ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        section("Tags") {
            VStack(alignment: .leading, spacing: 8) {
                if !task.tags.isEmpty {
                    FlowingTags(tags: task.tags) { tag in
                        var updated = task
                        updated.tags = TaskEdit.removingTag(tag, from: task.tags)
                        onChange(updated)
                    }
                }

                if task.tags.count < TaskTextParser.maxTags {
                    TextField("Add a tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .tag)
                        .onSubmit(commitTag)
                } else {
                    Text("Five tags is the limit.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Recurrence

    private var recurrenceSection: some View {
        section("Repeats") {
            Menu(task.recurrence?.displayName ?? "Never") {
                Button("Never") { setRecurrence(nil) }
                Divider()
                ForEach(TaskRecurrence.Unit.allCases, id: \.rawValue) { unit in
                    Button("Every \(unit.rawValue)") {
                        setRecurrence(TaskRecurrence(unit: unit, interval: 1))
                    }
                }
            }
            .fixedSize()
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        section("Notes") {
            TextEditor(text: $notesDraft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .focused($focus, equals: .notes)
                .padding(6)
                .background(
                    AppThemeConstants.textInputBackground,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                )
        }
    }

    // MARK: - Source meeting

    @ViewBuilder
    private var sourceSection: some View {
        if let meetingTitle {
            section("From") {
                Button(action: onOpenSource) {
                    Label(meetingTitle, systemImage: "waveform")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppThemeConstants.accent)
                .help("Open the meeting this came from")
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete Task", systemImage: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppThemeConstants.error)
        .padding(.top, 4)
    }

    // MARK: - Section chrome

    private func section(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: - Editing

    private func loadDrafts() {
        titleDraft = task.title
        notesDraft = task.notes
        draftSource = task
    }

    /// Writes the free-text fields back, but only when they actually differ — an inspector
    /// that saves on every focus change would stamp `updatedAt` and rewrite the file just
    /// for being looked at, which reorders any list sorted by recency.
    ///
    /// Writes to the task the drafts were loaded from, never to whichever task is on screen
    /// now. Selecting another row replaces `task` before this runs, so building the update
    /// from `task` wrote the previous row's title and notes onto the newly-selected one —
    /// which in markdown mode also renamed its file and trashed the original. Two clicks, no
    /// typing required. Keeping the source means a half-typed title is saved to the row it
    /// was typed into rather than dropped.
    private func commitDrafts() {
        guard let source = draftSource else { return }
        var updated = source
        var changed = false

        let sanitised = TaskTextParser.sanitisedTitle(titleDraft)
        if sanitised != source.title {
            updated.title = sanitised
            changed = true
        }
        if notesDraft != source.notes {
            updated.notes = notesDraft
            changed = true
        }
        guard changed else { return }
        onChange(updated)
    }

    private func commitTag() {
        let tags = TaskEdit.addingTag(newTag, to: task.tags)
        newTag = ""
        guard tags != task.tags else { return }
        var updated = task
        updated.tags = tags
        onChange(updated)
    }

    private func setRecurrence(_ recurrence: TaskRecurrence?) {
        var updated = task
        updated.recurrence = recurrence
        onChange(updated)
    }
}

// MARK: - FlowingTags

/// The task's tags as removable chips, wrapping onto as many lines as they need.
private struct FlowingTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                FilterChip(label: tag, style: .removable) {
                    onRemove(tag)
                }
            }
        }
    }
}
