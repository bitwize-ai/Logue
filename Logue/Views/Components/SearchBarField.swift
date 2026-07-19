import SwiftUI

/// Reusable search bar with magnifying glass icon, clear button, and rounded background.
/// Includes 300ms debounce so the parent binding only updates after the user stops typing.
///
/// Used in meeting list, docs home, and transcript timeline.
///
/// Usage:
/// ```
/// SearchBarField(text: $searchText, placeholder: "Search meetings")
/// ```
struct SearchBarField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    /// When `true`, the search bar stretches to fill available width instead of using a fixed width.
    var expandable: Bool = false

    @State private var localText = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(placeholder, text: $localText)
                .textFieldStyle(.plain)
                .frame(width: expandable ? nil : 180)
            if !localText.isEmpty {
                Button {
                    localText = ""
                    debounceTask?.cancel()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search")
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium))
        .onAppear { localText = text }
        .onChange(of: localText) { _, newValue in
            debounceTask?.cancel()
            if newValue.isEmpty {
                text = ""
            } else {
                debounceTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.searchDebounce)
                    if !Task.isCancelled {
                        text = newValue
                    }
                }
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue != localText {
                localText = newValue
            }
        }
    }
}
