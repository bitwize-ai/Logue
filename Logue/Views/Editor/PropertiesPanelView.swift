import SwiftUI

/// Edits a document's typed properties — the frontmatter-style metadata that
/// drives saved views and relationships.
struct PropertiesPanelView: View {
    let document: WritingDocument
    let onChange: (WritingDocument) -> Void

    @State private var newKey = ""
    @State private var showingAddField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                existingProperties
                suggestedProperties
                addCustomProperty
            }
            .padding(16)
        }
    }

    // MARK: - Existing

    @ViewBuilder
    private var existingProperties: some View {
        if document.propertyKeys.isEmpty {
            Text("No properties yet. Add one below to make this document filterable.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(document.propertyKeys, id: \.self) { key in
                    PropertyRow(
                        key: key,
                        value: document.property(key),
                        onEdit: { updated in setProperty(key, value: updated) },
                        onRemove: { setProperty(key, value: nil) }
                    )
                }
            }
        }
    }

    // MARK: - Suggested

    /// Well-known properties the document does not have yet, offered as one-tap adds
    /// so the common metadata is discoverable without typing a key.
    @ViewBuilder
    private var suggestedProperties: some View {
        let missing = PropertyKey.allCases.filter { document.property($0.rawValue) == nil }

        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add")
                    .font(.subheadline.weight(.semibold))

                FlowLayout(spacing: 6) {
                    ForEach(missing, id: \.self) { suggestion in
                        Button(suggestion.label) {
                            setProperty(
                                suggestion.rawValue,
                                value: suggestion.suggestedKind == "date"
                                    ? .date(Date())
                                    : .text("")
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule().fill(AppThemeConstants.accent.opacity(0.12))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Custom

    private var addCustomProperty: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingAddField {
                HStack(spacing: 6) {
                    TextField("Property name", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(commitNewKey)

                    Button("Add", action: commitNewKey)
                        .font(.caption)
                        .disabled(PropertyKey.sanitisedKey(newKey) == nil)
                }

                if !newKey.isEmpty, PropertyKey.sanitisedKey(newKey) == nil {
                    Text("Names cannot start with an underscore or be only symbols.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showingAddField = true
                } label: {
                    Label("Custom property", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func commitNewKey() {
        guard PropertyKey.sanitisedKey(newKey) != nil else { return }
        setProperty(newKey, value: .text(""))
        newKey = ""
        showingAddField = false
    }

    private func setProperty(_ key: String, value: PropertyValue?) {
        var updated = document
        updated.setProperty(key, value: value)
        onChange(updated)
    }
}

// MARK: - Row

private struct PropertyRow: View {
    let key: String
    let value: PropertyValue?
    let onEdit: (PropertyValue) -> Void
    let onRemove: () -> Void

    @State private var draft = ""
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(key)")
                }
            }

            editor
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var editor: some View {
        switch value {
        case let .boolean(flag):
            Toggle("", isOn: Binding(get: { flag }, set: { onEdit(.boolean($0)) }))
                .labelsHidden()

        case let .date(date):
            DatePicker(
                "",
                selection: Binding(get: { date }, set: { onEdit(.date($0)) }),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)

        default:
            TextField("Value", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onAppear { draft = value?.displayString ?? "" }
                .onChange(of: draft) { _, newValue in
                    // Keep list values as lists so filters can match individual entries.
                    if case .list = value {
                        onEdit(.list(newValue.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }))
                    } else {
                        onEdit(.text(newValue))
                    }
                }
        }
    }
}
