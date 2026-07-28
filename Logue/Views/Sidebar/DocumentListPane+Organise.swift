import SwiftUI

// MARK: - Creating and managing saved views and types

/// The write half of saved views and document types.
///
/// Everything that *reads* them was already here — the Views and Types sections of the filter menu,
/// the type context menu, `documents(matching:)` — but nothing created one, so `savedViews` was
/// permanently empty, the section guarded by `!store.savedViews.isEmpty` could never render, and
/// `SavedView`'s whole filter engine was reachable only from tests. An on-disk schema nothing can
/// produce is a migration liability for no benefit, so this closes the loop rather than shipping it.
extension DocumentListPane {
    // MARK: - Saved views

    /// Captures whatever the list is currently showing as a named view.
    ///
    /// A saved view is a filter, and the filter the user already built is the one they want to keep;
    /// asking them to rebuild it in a separate editor is the reason feature like this goes unused.
    func saveCurrentFilterAsView(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.addSavedView(
            SavedView(
                name: trimmed,
                filter: currentFilterGroup(),
                sort: sortOrder.asSavedViewSort,
                symbolName: filterMode.icon
            )
        )
    }

    /// The current pane state expressed as a filter.
    ///
    /// An empty condition list matches everything, which is what "All Documents" means — so the
    /// built-in modes that are not expressible as conditions save as an everything-view with the
    /// sort that was in use, rather than as an empty list the user has to debug.
    private func currentFilterGroup() -> FilterGroup {
        var conditions: [FilterCondition] = []

        switch filterMode {
        case .all:
            break
        case .recent:
            // "Recent" is an ordering, not a predicate, so it saves as the sort below.
            break
        case .inbox:
            conditions.append(
                FilterCondition(field: .isOrganised, comparator: .is, value: "false")
            )
        case .pinned:
            conditions.append(
                FilterCondition(field: .isPinned, comparator: .is, value: "true")
            )
        }

        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            conditions.append(FilterCondition(field: .title, comparator: .contains, value: search))
        }

        return FilterGroup(logic: .all, conditions: conditions)
    }

    func renameSavedView(_ view: SavedView, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = view
        updated.name = trimmed
        store.updateSavedView(updated)
    }

    func deleteSavedView(_ view: SavedView) {
        // Selection first: leaving `activeSavedViewID` pointing at a view that no longer exists
        // makes `documents(matching:)` fall back to every document, which looks like the filter
        // silently stopped working.
        if activeSavedViewID == view.id {
            activeSavedViewID = nil
        }
        store.deleteSavedView(id: view.id)
    }

    // MARK: - Document types

    /// Makes a type out of a document, so its shape can be applied to the next one.
    ///
    /// Built from an existing document rather than from an empty form: the properties a document
    /// already has are the ones worth templating, and it means the feature needs no editor.
    func createType(from document: WritingDocument, named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.addDocumentType(
            DocumentType(
                name: trimmed,
                symbolName: "doc.text",
                defaultProperties: document.properties ?? [:]
            )
        )
    }

    func renameType(_ type: DocumentType, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // The filter tracks types by name, so it has to follow the rename or the list empties.
        if activeTypeName == type.name {
            activeTypeName = trimmed
        }

        var updated = type
        updated.name = trimmed
        store.updateDocumentType(updated)
    }

    func deleteType(_ type: DocumentType) {
        if activeTypeName == type.name {
            activeTypeName = nil
        }
        store.deleteDocumentType(id: type.id)
    }

    /// Applies whatever the naming sheet was for.
    func commitOrganisePrompt(_ prompt: OrganisePrompt, name: String) {
        switch prompt {
        case .newView:
            saveCurrentFilterAsView(named: name)
        case let .renameView(view):
            renameSavedView(view, to: name)
        case let .newType(document):
            createType(from: document, named: name)
        case let .renameType(type):
            renameType(type, to: name)
        }
    }
}

// MARK: - Naming prompt

/// What the naming sheet is currently for.
///
/// One piece of state rather than a boolean per action, so two prompts cannot be up at once and
/// there is no invariant to maintain by hand — the same reason the filter state below became an enum.
enum OrganisePrompt: Identifiable {
    case newView
    case renameView(SavedView)
    case newType(WritingDocument)
    case renameType(DocumentType)

    var id: String {
        switch self {
        case .newView: "newView"
        case let .renameView(view): "renameView-\(view.id)"
        case let .newType(document): "newType-\(document.id)"
        case let .renameType(type): "renameType-\(type.id)"
        }
    }

    var title: String {
        switch self {
        case .newView: "Save as View"
        case .renameView: "Rename View"
        case .newType: "New Type"
        case .renameType: "Rename Type"
        }
    }

    var prompt: String {
        switch self {
        case .newView: "Name this view. It keeps the filter and sort you are using now."
        case .renameView: "New name for this view."
        case .newType: "Name this type. It takes this document's properties as its defaults."
        case .renameType: "New name for this type."
        }
    }

    /// The name to start with, so renaming does not begin from an empty field.
    var initialName: String {
        switch self {
        case .newView, .newType: ""
        case let .renameView(view): view.name
        case let .renameType(type): type.name
        }
    }
}

/// A single-field naming sheet, shared by all four actions.
struct OrganiseNamingSheet: View {
    let prompt: OrganisePrompt
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title)
                .font(.headline)
            Text(prompt.prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            name = prompt.initialName
            isFocused = true
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}
