import SwiftUI

/// Reading, writing and sharing skills.
///
/// The built-ins are listed first and are **readable**, which #64 asks for in as many words:
/// someone writing their first skill should have a worked one in front of them rather than an
/// empty box. Opening one shows exactly what it says to the model.
///
/// Editing a built-in copies it. That is decided in `SkillStore` rather than here — the
/// built-ins are documentation as much as they are features, and someone who overwrote the
/// only worked example has no way back. "Restore" is the way back, and it appears only on the
/// ones that have been changed.
struct SkillsSection: View {
    @State private var store = SkillStore.shared

    @State private var editingID: UUID?
    @State private var isAdding = false
    @State private var draft = Draft()
    @State private var rejection: SkillName.Rejection?

    /// What the form is holding, before it is a skill.
    private struct Draft {
        var title = ""
        var summary = ""
        var instructions = ""
        /// The tool list as typed. Parsed on save so a half-finished line is not an error.
        var tools = ""
        /// Whether this skill narrows at all. Absent and empty mean different things —
        /// see `AgentSkill.allowedToolNames` — so the switch is real state, not `tools.isEmpty`.
        var narrowsTools = false
        var editingBuiltIn = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(store.skills) { skill in
                if editingID == skill.id {
                    form
                } else {
                    row(for: skill)
                }
            }

            if isAdding {
                form
            } else if editingID == nil {
                HStack(spacing: 12) {
                    Button("Add a skill…") { beginAdding() }
                        .buttonStyle(.link)
                    Button("Import…") { importSkills() }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Skills").font(.headline)
            Text(
                "A skill is a set of instructions you can invoke by name from either composer. "
                    + "Logue's own rules still apply; a skill is added on top of them, and can only "
                    + "narrow which tools the agent may use."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - A skill

    private func row(for skill: AgentSkill) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.title).font(.callout)
                    Text("/\(skill.invocation)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if skill.isBuiltIn {
                        Text("built-in")
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
                if !skill.summary.isEmpty {
                    Text(skill.summary).font(.caption).foregroundStyle(.secondary)
                }
                Text(toolSummary(for: skill))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Edit") { beginEditing(skill) }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Edit \(skill.title)")
            Button("Export") { SkillTransfer.export(skill) }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Export \(skill.title)")
            if store.overriddenBuiltInIDs.contains(skill.id) {
                Button("Restore") { store.restore(id: skill.id) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("Restore the built-in \(skill.title)")
            } else if !skill.isBuiltIn {
                Button("Remove") { store.remove(id: skill.id) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.error)
                    .accessibilityLabel("Remove \(skill.title)")
            }
        }
        .padding(.vertical, 4)
    }

    /// What a skill's tool list means, in words.
    ///
    /// The three states read very differently and are easy to confuse in a list: not
    /// narrowing at all, narrowing to some, and narrowing to none.
    private func toolSummary(for skill: AgentSkill) -> String {
        guard let allowed = skill.allowedToolNames else { return "Any tool the agent has" }
        return allowed.isEmpty ? "No tools" : "Only: \(allowed.joined(separator: ", "))"
    }

    // MARK: - The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.editingBuiltIn {
                Text("Saving keeps your version and hides the built-in. Restore brings it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $draft.title)
                .textFieldStyle(.roundedBorder)
            Text("Invoked as /\(SkillName.invocation(from: draft.title))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            TextField("What it is for", text: $draft.summary)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $draft.instructions)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .accessibilityLabel("Instructions")

            // Said while it is still editable, not discovered later. Only a bounded amount
            // of a skill ever reaches the model — the rest is stored and never used, which
            // is the kind of thing you would otherwise find out from an answer that ignored
            // half of what you wrote.
            if let notice = lengthNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(draft.instructions.count > SkillFile.maxBodyCharacters
                        ? AppThemeConstants.error
                        : .secondary)
            }

            Toggle("Limit which tools this skill may use", isOn: $draft.narrowsTools)
                .font(.callout)
            if draft.narrowsTools {
                TextField("get_document, rephrase_text", text: $draft.tools)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Only these, and only if they are already available. A skill can take tools "
                        + "away; it can never add one you have turned off."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let rejection {
                Text(rejection.message)
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.error)
            }

            HStack {
                Button("Cancel") { cancel() }
                Button(editingID == nil ? "Add" : "Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            }
        }
        .padding(.vertical, 4)
    }

    /// What to say about how long the instructions are.
    ///
    /// Two different limits, and they mean different things. Past
    /// `AgentSkill.maxInstructionCharacters` the extra is *stored but never sent* — a skill
    /// is layered on top of the system prompt and everything else the turn needs, so it
    /// spends context the conversation would otherwise have. Past
    /// `SkillFile.maxBodyCharacters` it will not save at all.
    private var lengthNotice: String? {
        let count = draft.instructions.count
        if count > SkillFile.maxBodyCharacters {
            return "Too long to save — \(count) characters, and the limit is \(SkillFile.maxBodyCharacters)."
        }
        if count > AgentSkill.maxInstructionCharacters {
            return "Only the first \(AgentSkill.maxInstructionCharacters) characters are sent to the model. "
                + "The rest is saved but never used."
        }
        return nil
    }

    // MARK: - Doing things

    /// Refuses rather than silently cutting: losing what someone typed on save is the one
    /// failure here that cannot be undone.
    private var canCommit: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.instructions.count <= SkillFile.maxBodyCharacters
    }

    private func beginAdding() {
        editingID = nil
        rejection = nil
        draft = Draft()
        isAdding = true
    }

    private func beginEditing(_ skill: AgentSkill) {
        isAdding = false
        rejection = nil
        draft = Draft(
            title: skill.title,
            summary: skill.summary,
            instructions: skill.instructions,
            tools: skill.allowedToolNames?.joined(separator: ", ") ?? "",
            narrowsTools: skill.allowedToolNames != nil,
            editingBuiltIn: skill.isBuiltIn
        )
        editingID = skill.id
    }

    private func cancel() {
        isAdding = false
        editingID = nil
        rejection = nil
        draft = Draft()
    }

    private func commit() {
        let skill = AgentSkill(
            id: editingID ?? UUID(),
            title: draft.title,
            summary: draft.summary,
            instructions: draft.instructions,
            allowedToolNames: draft.narrowsTools ? parsedTools : nil
        )
        let result = editingID == nil ? store.add(skill) : store.update(skill)
        switch result {
        case .success:
            cancel()
        case let .failure(reason):
            // Kept open with what was typed still in it. The name rules are the store's, and
            // this reports them rather than keeping a second copy that can disagree.
            rejection = reason
        }
    }

    /// The tool list as typed, split and cleaned.
    ///
    /// Commas or whitespace, because someone will use either, and a list that only accepts
    /// one of them is a list that silently drops half of what was typed.
    private var parsedTools: [String] {
        draft.tools
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private func importSkills() {
        Task { await SkillTransfer.importSkills(into: store) }
    }
}
