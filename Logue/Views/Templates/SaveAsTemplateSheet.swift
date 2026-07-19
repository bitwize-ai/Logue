import SwiftUI

/// Common icons for template creation — curated subset of SF Symbols.
private let templateIconOptions: [(name: String, symbol: String)] = [
    ("Document", "doc.text"),
    ("Note", "note.text"),
    ("List", "list.bullet"),
    ("Checklist", "checklist"),
    ("Clipboard", "clipboard"),
    ("Book", "book"),
    ("Lightbulb", "lightbulb"),
    ("Star", "star"),
    ("Flag", "flag"),
    ("Chart", "chart.bar"),
    ("Person", "person"),
    ("Calendar", "calendar"),
    ("Folder", "folder"),
    ("Gear", "gearshape"),
    ("Pencil", "pencil.and.outline"),
    ("Code", "chevron.left.forwardslash.chevron.right"),
]

/// Sheet for saving an existing document as a reusable template.
struct SaveAsTemplateSheet: View {
    let document: WritingDocument
    @Environment(TemplateStore.self) private var templateStore
    @Environment(\.dismiss) private var dismiss

    @State private var templateName: String = ""
    @State private var selectedCategory: TemplateCategory = .personal
    @State private var selectedIcon: String = "doc.text"
    @State private var templateDescription: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Save as Template")
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

            // Form
            Form {
                TextField("Template Name", text: $templateName)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(TemplateCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }

                TextField("Description (optional)", text: $templateDescription)

                LabeledContent("Icon") {
                    iconPicker
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Template") {
                    let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    templateStore.saveDocumentAsTemplate(
                        title: name,
                        body: document.body,
                        category: selectedCategory,
                        icon: selectedIcon,
                        description: templateDescription
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(AppThemeConstants.paddingLarge)
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 380, maxHeight: 440)
        .background(AppThemeConstants.contentBackground)
        .onAppear {
            templateName = document.title
        }
    }

    // MARK: - Icon Picker

    private var iconPicker: some View {
        let columns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(templateIconOptions, id: \.symbol) { option in
                Button {
                    selectedIcon = option.symbol
                } label: {
                    Image(systemName: option.symbol)
                        .font(.callout)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(selectedIcon == option.symbol ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIcon == option.symbol
                                    ? AppThemeConstants.accent
                                    : AppThemeConstants.quaternaryFill)
                        )
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
        }
    }
}
