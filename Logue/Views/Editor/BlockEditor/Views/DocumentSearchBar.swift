import SwiftUI

/// Compact find bar overlay for in-document search, matching Apple's Cmd+F style.
struct DocumentSearchBar: View {
    @Bindable var searchState: DocumentSearchState
    var onNavigate: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("Find in document", text: $searchState.query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFieldFocused)
                .frame(minWidth: 120, maxWidth: 200)
                .onSubmit {
                    if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                        searchState.previousMatch()
                    } else {
                        searchState.nextMatch()
                    }
                    onNavigate()
                }

            if !searchState.query.isEmpty {
                Text(searchState.matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Divider()
                .frame(height: 16)

            Toggle(isOn: $searchState.matchCase) {
                Text("Aa")
                    .font(.caption.weight(.medium))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(searchState.matchCase ? AppThemeConstants.accent : .secondary)
            .help("Match Case")
            .accessibilityLabel("Match Case")

            Toggle(isOn: $searchState.wholeWord) {
                Text("W")
                    .font(.caption.weight(.bold))
                    .underline()
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(searchState.wholeWord ? AppThemeConstants.accent : .secondary)
            .help("Match Whole Word")
            .accessibilityLabel("Match Whole Word")

            Divider()
                .frame(height: 16)

            Button {
                searchState.previousMatch()
                onNavigate()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)
            .accessibilityLabel("Previous match")

            Button {
                searchState.nextMatch()
                onNavigate()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)
            .accessibilityLabel("Next match")

            Button {
                searchState.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onAppear { isFieldFocused = true }
        .onKeyPress(.escape) {
            searchState.close()
            return .handled
        }
    }
}
