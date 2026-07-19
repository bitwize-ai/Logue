import SwiftUI

/// Shared sheet for editing a custom template's name, description, and body.
struct EditTemplateSheet: View {
    let template: DocumentTemplate
    @Environment(TemplateStore.self) private var templateStore
    @Environment(\.dismiss) private var dismiss

    @State private var editName = ""
    @State private var editDescription = ""
    @State private var editBody = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Template")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(AppThemeConstants.paddingLarge)

            Divider()

            Form {
                TextField("Name", text: $editName)
                TextField("Description", text: $editDescription)

                VStack(alignment: .leading, spacing: AppThemeConstants.paddingSmall) {
                    Text("Body")
                        .font(.subheadline)
                        .foregroundStyle(AppThemeConstants.mutedText)
                    TextEditor(text: $editBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .background(AppThemeConstants.textInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                                .stroke(AppThemeConstants.borderColor, lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = template
                    updated.name = editName
                    updated.description = editDescription
                    updated.body = editBody
                    templateStore.updateTemplate(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(AppThemeConstants.paddingLarge)
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 400, maxHeight: 600)
        .background(AppThemeConstants.contentBackground)
        .onAppear {
            editName = template.name
            editDescription = template.description
            editBody = template.body
        }
    }
}
