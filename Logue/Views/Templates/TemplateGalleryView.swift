import os.log
import SwiftUI
import UniformTypeIdentifiers

/// Browsable gallery of document templates, shown as the detail pane
/// when "Templates" is selected in the sidebar.
struct TemplateGalleryView: View {
    @Environment(TemplateStore.self) private var templateStore
    @Environment(DocumentStore.self) private var documentStore

    @State private var searchText = ""
    @State private var selectedCategory: TemplateCategory?
    @State private var selectedTemplate: DocumentTemplate?
    @AppStorage("templateViewMode") private var viewModeRaw = ContentViewMode.grid.rawValue

    // Import sheet state
    @State private var importedFileContent: String?
    @State private var showImportSheet = false
    @State private var importName = ""
    @State private var importCategory: TemplateCategory = .business
    @State private var importDescription = ""

    // Context menu actions
    @State private var templateToDelete: DocumentTemplate?
    @State private var templateToEdit: DocumentTemplate?

    private var viewMode: ContentViewMode {
        ContentViewMode(rawValue: viewModeRaw) ?? .grid
    }

    // MARK: - Filtered Templates

    private var filteredTemplates: [DocumentTemplate] {
        var result = templateStore.templates

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// Templates grouped by category, preserving `TemplateCategory.allCases` order.
    private var groupedTemplates: [(category: TemplateCategory, templates: [DocumentTemplate])] {
        let grouped = Dictionary(grouping: filteredTemplates, by: \.category)
        return TemplateCategory.allCases.compactMap { category in
            guard let templates = grouped[category], !templates.isEmpty else { return nil }
            return (category, templates)
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if filteredTemplates.isEmpty {
                emptyState
            } else if viewMode == .grid {
                templateGrid
            } else {
                templateList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Templates")
        .navigationSubtitle("\(filteredTemplates.count) template\(filteredTemplates.count == 1 ? "" : "s")")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search templates")
        .toolbar { galleryToolbarContent }
        // Arch-5: Sheets must explicitly propagate @Environment for @Observable
        .sheet(item: $selectedTemplate) { template in
            TemplatePreviewView(template: template)
                .environment(templateStore)
                .environment(documentStore)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportTemplateSheet(
                fileContent: importedFileContent ?? "",
                name: $importName,
                category: $importCategory,
                description: $importDescription,
                templateStore: templateStore,
                onDismiss: {
                    showImportSheet = false
                    importedFileContent = nil
                    importName = ""
                    importDescription = ""
                }
            )
        }
        .alert("Delete Template", isPresented: Binding(
            get: { templateToDelete != nil },
            set: {
                if !$0 {
                    templateToDelete = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) { templateToDelete = nil }
            Button("Delete", role: .destructive) {
                if let template = templateToDelete {
                    templateStore.deleteTemplate(id: template.id)
                    templateToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(templateToDelete?.name ?? "")\"? This cannot be undone.")
        }
        .sheet(item: $templateToEdit) { template in
            EditTemplateSheet(template: template)
                .environment(templateStore)
        }
    }

    // MARK: - Use Template

    private func useTemplate(_ template: DocumentTemplate) {
        let doc = documentStore.createDocument(title: template.name, body: template.body)
        documentStore.selectedDocumentID = doc.id
    }

    // MARK: - Duplicate as Custom

    private func duplicateAsCustom(_ template: DocumentTemplate) {
        templateStore.createTemplate(
            name: "\(template.name) (Copy)",
            category: template.category,
            icon: template.icon,
            description: template.description,
            body: template.body
        )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func templateContextMenu(for template: DocumentTemplate) -> some View {
        Button {
            useTemplate(template)
        } label: {
            Label("Use Template", systemImage: "doc.badge.plus")
        }

        Button {
            selectedTemplate = template
        } label: {
            Label("Preview", systemImage: "eye")
        }

        Divider()

        if template.isBuiltIn {
            Button {
                duplicateAsCustom(template)
            } label: {
                Label("Duplicate as Custom", systemImage: "doc.on.doc")
            }
        } else {
            Button {
                templateToEdit = template
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                duplicateAsCustom(template)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                templateToDelete = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var galleryToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                importMarkdownTemplate()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .accessibilityLabel("Import Template")
            }
            .help("Import Template")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Section("View") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModeRaw = ContentViewMode.list.rawValue
                        }
                    } label: {
                        HStack {
                            Label("List", systemImage: "list.bullet")
                            if viewMode == .list {
                                Spacer(); Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModeRaw = ContentViewMode.grid.rawValue
                        }
                    } label: {
                        HStack {
                            Label("Grid", systemImage: "square.grid.2x2")
                            if viewMode == .grid {
                                Spacer(); Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Section("Category") {
                    Button {
                        selectedCategory = nil
                    } label: {
                        HStack {
                            Label("All Categories", systemImage: "square.grid.2x2")
                            if selectedCategory == nil {
                                Spacer(); Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(TemplateCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Label(category.rawValue, systemImage: category.icon)
                                if selectedCategory == category {
                                    Spacer(); Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Options")
            .accessibilityLabel("Options")
        }
    }

    // MARK: - Grid View

    private var templateGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedTemplates, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        categoryHeader(group.category, count: group.templates.count)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(group.templates) { template in
                                TemplateCardView(template: template) {
                                    selectedTemplate = template
                                }
                                .contextMenu {
                                    templateContextMenu(for: template)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(24)
        }
    }

    // MARK: - List View

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(groupedTemplates, id: \.category) { group in
                    categoryHeader(group.category, count: group.templates.count)
                        .padding(.top, 8)

                    ForEach(group.templates) { template in
                        TemplateRowView(template: template) {
                            selectedTemplate = template
                        }
                        .contextMenu {
                            templateContextMenu(for: template)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Category Header

    private func categoryHeader(_ category: TemplateCategory, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(category.rawValue)
                .font(.headline)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(AppThemeConstants.quaternaryFill)
                )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Templates" : "No Results",
                systemImage: searchText.isEmpty ? "doc.on.doc" : "magnifyingglass"
            )
        } description: {
            if searchText.isEmpty {
                if selectedCategory != nil {
                    Text("No templates in this category.")
                } else {
                    Text("Import a Markdown file to create your first template.")
                }
            } else {
                Text("No templates match '\(searchText)'")
            }
        } actions: {
            if searchText.isEmpty {
                Button("Import Template") {
                    importMarkdownTemplate()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import

    private func importMarkdownTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Select a Markdown file to import as a template"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            importedFileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Logger(subsystem: AppConstants.bundleID, category: "TemplateImport")
                .error("Failed to read template file: \(error.localizedDescription, privacy: .public)")
            importedFileContent = nil
        }
        importName = url.deletingPathExtension().lastPathComponent
        showImportSheet = true
    }
}

// MARK: - Template Card View (Grid)

private struct TemplateCardView: View {
    let template: DocumentTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.accent)

                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(template.description.isEmpty ? "No description" : template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

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
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(
                    color: .black.opacity(isHovered
                        ? AppThemeConstants.shadowOpacityHover
                        : AppThemeConstants.shadowOpacityDefault),
                    radius: isHovered
                        ? AppThemeConstants.shadowRadiusHover
                        : AppThemeConstants.shadowRadiusDefault,
                    y: 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(
                    isHovered ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isHovered)
        .overlay(HandCursorArea())
    }
}

// MARK: - Template Row View (List)

private struct TemplateRowView: View {
    let template: DocumentTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(template.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if !template.isBuiltIn {
                            Text("Custom")
                                .font(.caption2)
                                .foregroundStyle(AppThemeConstants.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight))
                                )
                        }
                    }
                    Text(template.description.isEmpty ? "No description" : template.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(template.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AppThemeConstants.quaternaryFill)
                    )
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(
                    color: .black.opacity(isHovered
                        ? AppThemeConstants.shadowOpacityHover
                        : AppThemeConstants.shadowOpacityDefault),
                    radius: isHovered
                        ? AppThemeConstants.shadowRadiusHover
                        : AppThemeConstants.shadowRadiusDefault,
                    y: 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(
                    isHovered ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isHovered)
        .overlay(HandCursorArea())
    }
}

// MARK: - Import Template Sheet

private struct ImportTemplateSheet: View {
    let fileContent: String
    @Binding var name: String
    @Binding var category: TemplateCategory
    @Binding var description: String
    let templateStore: TemplateStore
    let onDismiss: () -> Void

    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Template")
                    .font(.headline)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(AppThemeConstants.paddingLarge)

            Divider()

            Form {
                TextField("Name", text: $name)

                Picker("Category", selection: $category) {
                    ForEach(TemplateCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon)
                            .tag(cat)
                    }
                }

                TextField("Description (optional)", text: $description)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            // File content preview
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPreview.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(showPreview ? 90 : 0))
                        Text("File Preview")
                            .font(.subheadline.weight(.medium))
                        Text("\(fileContent.count) characters")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showPreview {
                    ScrollView {
                        Text(fileContent)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 150)
                    .background(AppThemeConstants.textInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                            .stroke(AppThemeConstants.borderColor, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, AppThemeConstants.paddingLarge)
            .padding(.bottom, AppThemeConstants.paddingMedium)

            Divider()

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else { return }
                    templateStore.createTemplate(
                        name: trimmedName,
                        category: category,
                        icon: "doc.text",
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: fileContent
                    )
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(AppThemeConstants.paddingLarge)
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 380, maxHeight: 560)
        .background(AppThemeConstants.contentBackground)
    }
}
