import SwiftUI

/// Templates as a panel of the All Documents surface.
///
/// A list rather than the gallery's grid: `TemplateGalleryView` lays out adaptive 200–280pt
/// columns, which collapses to a single column of cards in a panel this narrow — more
/// scrolling for less information. The grid is still the better way to browse, so it stays
/// one click away behind "Browse all" rather than being deleted.
struct TemplateListPanel: View {
    @Environment(TemplateStore.self) private var templateStore

    @State private var searchText = ""
    @State private var selectedCategory: TemplateCategory?
    @State private var previewing: DocumentTemplate?
    @State private var showGallery = false

    private var filteredTemplates: [DocumentTemplate] {
        templateStore.templates.filter { template in
            matchesCategory(template) && matchesSearch(template)
        }
    }

    private func matchesCategory(_ template: DocumentTemplate) -> Bool {
        guard let selectedCategory else { return true }
        return template.category == selectedCategory
    }

    private func matchesSearch(_ template: DocumentTemplate) -> Bool {
        guard !searchText.isEmpty else { return true }
        return template.name.localizedCaseInsensitiveContains(searchText)
            || template.description.localizedCaseInsensitiveContains(searchText)
    }

    /// Grouped for the same reason the gallery groups: 55 templates in one flat list is a
    /// scroll, not a choice.
    private var grouped: [(category: TemplateCategory, templates: [DocumentTemplate])] {
        let byCategory = Dictionary(grouping: filteredTemplates, by: \.category)
        return TemplateCategory.allCases.compactMap { category in
            guard let templates = byCategory[category], !templates.isEmpty else { return nil }
            return (category, templates.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if filteredTemplates.isEmpty {
                emptyState
            } else {
                templateList
            }

            Divider()
            browseAllButton
        }
        .background(AppThemeConstants.contentBackground)
        .sheet(item: $previewing) { template in
            TemplatePreviewView(template: template)
        }
        .sheet(isPresented: $showGallery) {
            gallerySheet
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            categoryPicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search templates", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            AppThemeConstants.surfaceBackground,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
        )
    }

    private var categoryPicker: some View {
        Menu {
            Button("All categories") { selectedCategory = nil }
            Divider()
            ForEach(TemplateCategory.allCases) { category in
                Button(category.rawValue) { selectedCategory = category }
            }
        } label: {
            Label(selectedCategory?.rawValue ?? "All categories", systemImage: "square.grid.2x2")
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by category")
    }

    // MARK: - List

    private var templateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.category.id) { group in
                    Section {
                        ForEach(group.templates) { template in
                            TemplateListRow(template: template) {
                                previewing = template
                            }
                        }
                    } header: {
                        sectionHeader(group.category)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func sectionHeader(_ category: TemplateCategory) -> some View {
        Text(category.rawValue.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppThemeConstants.contentBackground)
    }

    // MARK: - Browse all

    private var browseAllButton: some View {
        Button {
            showGallery = true
        } label: {
            Label("Browse all", systemImage: "square.grid.2x2")
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppThemeConstants.accent)
        .padding(.vertical, 10)
        .help("Open the full template gallery")
    }

    private var gallerySheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Templates")
                    .font(.headline)
                Spacer()
                Button("Done") { showGallery = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            TemplateGalleryView()
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Templates" : "No Matching Templates",
                systemImage: searchText.isEmpty ? "doc.on.doc" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                    ? "Templates you save will appear here."
                    : "No templates match \"\(searchText)\""
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

/// One template in the panel: icon, name, and the description that tells you what it is for.
private struct TemplateListRow: View {
    let template: DocumentTemplate
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: template.icon)
                    .font(.callout)
                    .foregroundStyle(AppThemeConstants.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !template.description.isEmpty {
                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                isHovered ? AppThemeConstants.surfaceBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(template.name), \(template.category.rawValue)")
    }
}
