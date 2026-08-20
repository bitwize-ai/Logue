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
    /// Applies a text edit to the task it was typed into, whatever that task holds now.
    ///
    /// Separate from `onChange` on purpose: the free-text fields are the only controls here
    /// whose value can be older than the record, because they are held as drafts while the
    /// user types. `TaskTextCommit` names the task and carries only the fields that actually
    /// changed, so a commit cannot bring a stale copy of anything else with it.
    let onCommitText: (TaskTextCommit) -> Void
    let onDelete: () -> Void
    let onOpenSource: () -> Void
    let onClose: () -> Void

    /// Fixed width for now. `LibraryPanelContainer` is what this would reuse to become
    /// resizable; it is not wired up here yet.
    private let panelWidth: CGFloat = 320

    @State private var newTag = ""
    /// The free-text fields and what they were loaded from. `TaskDrafts` holds the rule; this
    /// view only reports focus changes and edits into it.
    @State private var drafts: TaskDrafts?
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
        // Switching rows sends the outgoing row's text under the outgoing row's id, then loads
        // the new one. The id travels with the text, so nothing can land on the task that just
        // became selected.
        .onChange(of: task.id) {
            commitDrafts()
            loadDrafts()
        }
        .onChange(of: focus) { previous, _ in
            if previous != nil {
                commitDrafts()
            }
        }
        // A field the user is not typing in must never show text older than the record — a
        // rename made in the list row changes the title without changing the id, so nothing
        // above re-runs. `resynced` refuses a record from a different row, so this is safe
        // whatever order SwiftUI delivers these in.
        .onChange(of: task) { _, latest in
            guard let resynced = drafts?.resynced(with: latest, focused: focusedField) else {
                return
            }
            drafts = resynced
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
            TextField("Title", text: titleBinding, axis: .vertical)
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
            TextEditor(text: notesBinding)
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
        drafts = .loaded(from: task)
    }

    /// Which field the drafts should treat as being typed into.
    private var focusedField: TaskDrafts.Field? {
        switch focus {
        case .title: .title
        case .notes: .notes
        case .tag, nil: nil
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { drafts?.title ?? "" },
            set: { drafts = drafts?.edited(title: $0) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { drafts?.notes ?? "" },
            set: { drafts = drafts?.edited(notes: $0) }
        )
    }

    /// Sends whatever the user actually typed to the row they typed it into.
    ///
    /// The rule itself lives in `TaskDrafts` and `TaskTextCommit`, where it is covered by
    /// tests. It was got wrong three times while it lived here.
    private func commitDrafts() {
        guard let current = drafts, let commit = current.commit() else { return }
        onCommitText(commit)
        drafts = current.committed(commit)
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
