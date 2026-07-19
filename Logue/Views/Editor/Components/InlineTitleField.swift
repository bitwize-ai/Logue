import SwiftUI

struct InlineTitleField: View {
    let document: WritingDocument
    @Environment(DocumentStore.self) private var store
    @State private var editing = false
    @State private var titleDraft = ""
    @State private var isHovered = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        if editing {
            TextField("", text: $titleDraft, onCommit: commitTitle)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .focused($isFieldFocused)
                .onAppear {
                    titleDraft = document.title
                    Task {
                        try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                        isFieldFocused = true
                    }
                }
                .onExitCommand { editing = false }
        } else {
            HStack(spacing: 6) {
                Text(document.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                // Pencil affordance on hover — tells users the title is editable.
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                titleDraft = document.title
                editing = true
            }
            .help("Click to rename")
            .accessibilityLabel("Document title: \(document.title)")
            .accessibilityHint("Activate to rename")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func commitTitle() {
        editing = false
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = document
        updated.title = trimmed
        store.updateDocument(updated)
    }
}
