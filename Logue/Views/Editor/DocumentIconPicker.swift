import SwiftUI

/// Shows a document's icon where a list or card would otherwise show the document symbol.
///
/// The emoji takes the place of the symbol rather than sitting next to it, so a document
/// without an icon renders exactly as it did before icons existed — same glyph, same slot,
/// no placeholder and nothing that shifts when one is set.
struct DocumentIconLabel: View {
    let icon: String?
    /// The symbol drawn when there is no icon. Sites differ (`doc.text`, `doc.text.fill`),
    /// so the caller names the one it was already using.
    var fallbackSymbol: String = "doc.text"
    var font: Font = .title3
    /// Applied to the fallback symbol only — tinting an emoji does nothing useful.
    var fallbackStyle: Color?

    var body: some View {
        if let icon {
            Text(icon)
                .font(font)
        } else if let fallbackStyle {
            Image(systemName: fallbackSymbol)
                .font(font)
                .foregroundStyle(fallbackStyle)
        } else {
            Image(systemName: fallbackSymbol)
                .font(font)
                .foregroundStyle(.secondary)
        }
    }
}

/// A popover grid for picking a single-emoji icon for a document.
///
/// Separate from `SpaceIconPicker`, which offers SF Symbol *names*: a document icon is a
/// single grapheme (see `DocumentIcon`), so a symbol name could never be a valid value for
/// one. Every path out of here — grid or typed field — goes through `DocumentIcon.sanitised`,
/// so nothing that would be rejected downstream can be assigned in the first place.
struct DocumentIconPicker: View {
    let currentIcon: String?
    /// Called with the sanitised icon, or `nil` to clear it.
    let onSelect: (String?) -> Void

    @State private var customIcon = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.emojiGroups, id: \.0) { group, emoji in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8),
                                spacing: 4
                            ) {
                                ForEach(emoji, id: \.self) { icon in
                                    emojiButton(icon)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 300, height: 340)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                // A typed field as well as the grid, because the grid is a shortlist and any
                // single grapheme is a legal icon. `sanitised` is what decides, not this field.
                TextField("Type any emoji…", text: $customIcon)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { commitCustomIcon() }
                    .accessibilityLabel("Custom document icon")
                    .accessibilityHint("Type a single emoji and press Return")

                if !customIcon.isEmpty {
                    Button("Use") { commitCustomIcon() }
                        .controlSize(.small)
                        .disabled(DocumentIcon.sanitised(customIcon) == nil)
                }
            }
            .padding(8)
            .background(
                Color.primary.opacity(AppThemeConstants.opacityLight),
                in: RoundedRectangle(cornerRadius: 6)
            )

            Button {
                onSelect(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slash.circle")
                        .frame(width: 20)
                    Text("No icon")
                        .font(.caption)
                    Spacer()
                    if currentIcon == nil {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(AppThemeConstants.brandPrimary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No document icon")
            .accessibilityHint("Removes the document's icon")
            .accessibilityAddTraits(currentIcon == nil ? .isSelected : [])
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func emojiButton(_ icon: String) -> some View {
        Button {
            onSelect(DocumentIcon.sanitised(icon))
        } label: {
            Text(icon)
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(currentIcon == icon
                            ? AppThemeConstants.brandPrimary.opacity(AppThemeConstants.opacityMedium)
                            : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            currentIcon == icon ? AppThemeConstants.brandPrimary : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityHint("Sets the document icon")
        .accessibilityAddTraits(currentIcon == icon ? .isSelected : [])
    }

    /// Applies the typed icon, ignoring anything `DocumentIcon` rejects.
    ///
    /// Silently declining is deliberate: the "Use" button is already disabled for input that
    /// would not survive validation, so reaching here with something invalid means a Return
    /// key on an empty or multi-character field, where an error would be noise.
    private func commitCustomIcon() {
        guard let sanitised = DocumentIcon.sanitised(customIcon) else { return }
        customIcon = ""
        onSelect(sanitised)
    }

    // MARK: - Emoji Library

    /// A shortlist for the grid. Not exhaustive by design — the typed field covers the rest.
    static let emojiGroups: [(String, [String])] = [
        ("General", [
            "📄", "📝", "📋", "📌", "📎", "🔖", "🗂", "📁",
            "⭐️", "❤️", "🔥", "✅", "❌", "⚠️", "❓", "💡",
        ]),
        ("Work", [
            "💼", "📊", "📈", "📉", "🗓", "⏰", "🎯", "🏆",
            "🤝", "💰", "🧾", "🏢", "✉️", "📞", "🖇", "🗒",
        ]),
        ("Product & Design", [
            "🎨", "🖌", "✏️", "📐", "🧩", "🪄", "🖼", "🎬",
            "🚀", "🛠", "🔧", "🧪", "🔬", "📦", "🧭", "🗺",
        ]),
        ("Engineering", [
            "💻", "🖥", "⌨️", "🐛", "🔒", "🔑", "☁️", "🗄",
            "⚙️", "🧱", "🔌", "📡", "🤖", "🧠", "♻️", "🔍",
        ]),
        ("People & Places", [
            "👤", "👥", "🗣", "🎓", "🏠", "🌍", "✈️", "🚗",
            "☕️", "🍽", "🌱", "🌤", "🌙", "🎉", "🎁", "🎵",
        ]),
    ]
}
