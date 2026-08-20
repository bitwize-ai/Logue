import SwiftUI

/// Narrows the action item inbox to one meeting.
///
/// A popover rather than a `Menu`: the list is as long as the user has meetings, and a menu
/// cannot hold a search field. It also cannot be bounded — a plain menu of two hundred
/// meetings is a scroll to nowhere.
struct MeetingFilterPicker: View {
    /// Meetings that have items under the current filter, with how many.
    let meetings: [Entry]
    @Binding var selection: UUID?

    @State private var isPresented = false
    @State private var query = ""

    struct Entry: Identifiable, Equatable {
        let id: UUID
        let title: String
        let count: Int
    }

    /// Enough rows to scan, few enough that the popover stays a control rather than a window.
    private static let maxVisibleRows = 7
    private static let rowHeight: CGFloat = 28

    private var matches: [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }
        return meetings.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var selectedTitle: String {
        guard let selection, let match = meetings.first(where: { $0.id == selection })
        else { return "All meetings" }
        return match.title
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            // Compressible: a long meeting title must shorten the button, never widen the
            // panel past its own frame.
            .frame(minWidth: 0, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Show items from one meeting")
        .accessibilityLabel("Filter by meeting, \(selectedTitle)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            TextField("Search meetings", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(AppThemeConstants.paddingSmall)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    row(title: "All meetings", count: nil, id: nil)
                    if !matches.isEmpty {
                        Divider()
                    }
                    ForEach(matches) { entry in
                        row(title: entry.title, count: entry.count, id: entry.id)
                    }
                }
            }
            .frame(height: popoverListHeight)

            if matches.isEmpty, !query.isEmpty {
                Text("No meetings match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(AppThemeConstants.paddingSmall)
            }
        }
        .frame(width: 260)
    }

    /// Grows with the list up to the cap, so a two-meeting popover is not mostly empty space.
    private var popoverListHeight: CGFloat {
        let rows = min(matches.count + 1, Self.maxVisibleRows)
        return CGFloat(max(rows, 1)) * Self.rowHeight
    }

    private func row(title: String, count: Int?, id: UUID?) -> some View {
        Button {
            selection = id
            isPresented = false
            query = ""
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                // Only when there is something to count — a "(0)" is noise on a row that
                // would show nothing.
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selection == id {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(AppThemeConstants.accent)
                }
            }
            .padding(.horizontal, AppThemeConstants.paddingSmall)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0) items" } ?? title)
    }
}
