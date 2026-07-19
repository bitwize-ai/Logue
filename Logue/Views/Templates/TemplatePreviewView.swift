import SwiftUI
import Textual

struct TemplatePreviewView: View {
    let template: DocumentTemplate
    @Environment(DocumentStore.self) private var documentStore
    @Environment(TemplateStore.self) private var templateStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var templateToEdit: DocumentTemplate?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: template.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(AppThemeConstants.accent)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.title3)
                            .fontWeight(.semibold)

                        if !template.isBuiltIn {
                            Text("Custom")
                                .font(.caption2)
                                .foregroundStyle(AppThemeConstants.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight))
                                )
                        }
                    }

                    if !template.description.isEmpty {
                        Text(template.description)
                            .font(.subheadline)
                            .foregroundStyle(AppThemeConstants.mutedText)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppThemeConstants.paddingLarge)
            .padding(.vertical, AppThemeConstants.paddingMedium)

            Divider()

            // MARK: - Markdown Body Preview

            ScrollView {
                StructuredText(markdown: Self.renderCheckboxes(template.body))
                    .font(.callout)
                    .textual.structuredTextStyle(.gitHub)
                    .textual.inlineStyle(.gitHub)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppThemeConstants.paddingLarge)
            }

            Divider()

            // MARK: - Bottom Bar

            HStack {
                if template.isBuiltIn {
                    Button {
                        duplicateAsCustom()
                    } label: {
                        Label("Duplicate as Custom", systemImage: "doc.on.doc")
                    }
                } else {
                    Button {
                        templateToEdit = template
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Spacer()

                Button {
                    let doc = documentStore.createDocument(title: template.name, body: template.body)
                    documentStore.selectedDocumentID = doc.id
                    dismiss()
                } label: {
                    Label("Use Template", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
            }
            .padding(AppThemeConstants.paddingLarge)
        }
        .frame(minWidth: 600, maxWidth: 600, minHeight: 500, maxHeight: 700)
        .background(AppThemeConstants.contentBackground)
        .alert("Delete Template", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                templateStore.deleteTemplate(id: template.id)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(template.name)\"? This action cannot be undone.")
        }
        .sheet(item: $templateToEdit) { tmpl in
            EditTemplateSheet(template: tmpl)
                .environment(templateStore)
        }
    }

    private func duplicateAsCustom() {
        templateStore.createTemplate(
            name: "\(template.name) (Copy)",
            category: template.category,
            icon: template.icon,
            description: template.description,
            body: template.body
        )
        dismiss()
    }

    /// Converts markdown task list syntax to unicode checkboxes for rendering.
    private static func renderCheckboxes(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "- [x]", with: "- ☑")
            .replacingOccurrences(of: "- [X]", with: "- ☑")
            .replacingOccurrences(of: "- [ ]", with: "- ☐")
    }
}
