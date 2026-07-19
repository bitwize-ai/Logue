import SwiftUI

/// Sheet for saving a meeting's Smart Minutes as a markdown document.
struct SaveSummaryToDocumentSheet: View {
    @Binding var isPresented: Bool
    let meeting: MeetingNote
    /// Called after a successful save with the document ID.
    var onSaved: ((UUID) -> Void)?

    @Environment(DocumentStore.self) private var documentStore
    @Environment(SpaceStore.self) private var spaceStore

    // Selection state
    @State private var selectedSpaceID: UUID?
    @State private var documentTarget: DocumentTarget = .newDocument
    @State private var selectedDocumentID: UUID?
    @State private var newDocTitle = ""

    // New space inline creation
    @State private var showNewSpaceField = false
    @State private var newSpaceName = ""
    @FocusState private var isNewSpaceFocused: Bool

    enum DocumentTarget {
        case newDocument
        case existingDocument
    }

    // MARK: - Available Documents

    private var availableDocuments: [WritingDocument] {
        if let spaceID = selectedSpaceID {
            return documentStore.documents(inSpace: spaceID)
        }
        return documentStore.activeDocuments
    }

    private var canSave: Bool {
        switch documentTarget {
        case .newDocument:
            true
        case .existingDocument:
            selectedDocumentID != nil
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.accent)
                Text("Save to Document")
                    .font(.title3.bold())
            }

            // Space picker
            spaceSection

            // Document target
            targetSection

            // Conditional detail
            switch documentTarget {
            case .newDocument:
                titleField
            case .existingDocument:
                documentPicker
            }

            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses the save sheet without saving")

                Spacer()

                Button("Save") {
                    performSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityLabel("Save summary")
                .accessibilityHint("Saves the meeting summary to the selected document")
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            newDocTitle = "\(meeting.title) — Minutes"
        }
    }

    // MARK: - Space Section

    private var spaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Space")
                .font(.subheadline.weight(.medium))

            Picker("", selection: $selectedSpaceID) {
                Text("No Space").tag(UUID?.none)
                ForEach(spaceStore.topLevelSpaces) { space in
                    Label(space.name, systemImage: space.icon ?? "folder")
                        .tag(Optional(space.id))
                }
            }
            .labelsHidden()

            if showNewSpaceField {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Space name", text: $newSpaceName, onCommit: {
                        createNewSpace()
                    })
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewSpaceFocused)
                    .onExitCommand {
                        showNewSpaceField = false
                        newSpaceName = ""
                    }
                    Button("Add") {
                        createNewSpace()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)
                    .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add space")
                    .accessibilityHint("Creates a new space with the entered name")
                }
            } else {
                Button {
                    newSpaceName = ""
                    showNewSpaceField = true
                    Task {
                        try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                        isNewSpaceFocused = true
                    }
                } label: {
                    Label("New Space", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(AppThemeConstants.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New space")
                .accessibilityHint("Shows a field to create a new space")
            }
        }
    }

    private func createNewSpace() {
        let trimmed = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let space = spaceStore.createSpace(name: trimmed) else { return }
        selectedSpaceID = space.id
        showNewSpaceField = false
        newSpaceName = ""
    }

    // MARK: - Target Section

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save to")
                .font(.subheadline.weight(.medium))

            SelectableOptionCard(
                icon: "doc.badge.plus",
                title: "New Document",
                description: "Create a new document with the summary",
                isSelected: documentTarget == .newDocument
            ) {
                documentTarget = .newDocument
            }

            SelectableOptionCard(
                icon: "doc.text",
                title: "Existing Document",
                description: "Append the summary to an existing document",
                isSelected: documentTarget == .existingDocument
            ) {
                documentTarget = .existingDocument
            }
        }
    }

    // MARK: - New Document Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.subheadline.weight(.medium))
            TextField("Document title", text: $newDocTitle)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Existing Document Picker

    private var documentPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Document")
                .font(.subheadline.weight(.medium))

            if availableDocuments.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(selectedSpaceID != nil ? "No documents in this space" : "No documents available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                        .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
                )
            } else {
                Picker("", selection: $selectedDocumentID) {
                    Text("Select a document…").tag(UUID?.none)
                    ForEach(availableDocuments) { doc in
                        Text(doc.title).tag(Optional(doc.id))
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Save

    private func performSave() {
        let markdown = meeting.smartMinutesMarkdown()

        if documentTarget == .newDocument {
            let title = newDocTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(meeting.title) — Minutes"
                : newDocTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let doc = documentStore.createDocument(title: title, inSpace: selectedSpaceID)
            var updated = doc
            updated.body = markdown
            documentStore.updateDocument(updated)
            onSaved?(doc.id)
            isPresented = false
        } else if let existingID = selectedDocumentID,
                  let existing = documentStore.activeDocuments.first(where: { $0.id == existingID })
        {
            var updated = existing
            let separator = updated.body.isEmpty ? "" : "\n\n---\n\n"
            updated.body += separator + markdown
            documentStore.updateDocument(updated)
            onSaved?(existing.id)
            isPresented = false
        }
    }
}
