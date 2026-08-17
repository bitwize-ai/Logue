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

    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var newTag = ""
    /// The values the drafts were loaded with, and the row they came from.
    ///
    /// Kept to answer one question: did the *user* type something? Comparing the drafts
    /// against the live record instead reads an edit made elsewhere — a rename in the list —
    /// as a change made here, and writes the old text back over it.
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
        // Switching rows sends the outgoing row's text under the outgoing row's id, then
        // loads the new one. The id travels with the text, so nothing can land on the task
        // that just became selected.
        .onChange(of: task.id) {
            commitDrafts()
            loadDrafts()
        }
        .onChange(of: focus) { previous, _ in
            if previous != nil {
                commitDrafts()
            }
        }
        // A field the user is not typing in must never show text older than the record.
        // Renaming the row in the list changes `task.title` without changing `task.id`, so
        // nothing above re-runs: the field kept the old title, and an edit typed there sent
        // that stale value back as the base — undoing the rename, and in markdown mode
        // trashing the renamed file. The focused field is left alone, because resyncing it
        // would overwrite what is being typed.
        .onChange(of: task.title) { _, latest in
            guard focus != .title else { return }
            titleDraft = latest
            draftSource?.title = latest
        }
        .onChange(of: task.notes) { _, latest in
            guard focus != .notes else { return }
            notesDraft = latest
            draftSource?.notes = latest
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
    /// Sends the typed title and notes to the row they were typed into.
    ///
    /// Two separate questions, and answering both from one record is what kept going wrong.
    /// *Did the user type something?* is answered against `draftSource`, the values the fields
    /// were loaded with — comparing against the live record instead means an edit made
    /// elsewhere reads as something typed here, so renaming the task in the list and closing
    /// the inspector wrote the old title back over it. *What should the text be applied to?*
    /// is not this view's question at all: it hands over the id and the two strings, and the
    /// owner applies them to whatever that task holds now.
    ///
    /// Carrying a whole `TaskItem` is what made this unfixable from here. A text commit built
    /// on the live record wrote the outgoing row's text onto the incoming one when the
    /// selection had already moved; built on the snapshot, it reverted every field changed
    /// since selection — a due date, a priority, a tag, or the list row's completion tick,
    /// which took `completedCount` back with it.
    private func commitDrafts() {
        guard var source = draftSource,
              let commit = TaskTextCommit.make(
                  loadedFrom: source, titleDraft: titleDraft, notesDraft: notesDraft
              )
        else { return }

        onCommitText(commit)

        // What was just committed is what the fields now hold, so a later blur with no further
        // typing has nothing to send. Applied to the loaded values rather than reassigned from
        // the drafts, so the sanitised title is what is remembered.
        source = commit.applied(to: source) ?? source
        draftSource = source
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
