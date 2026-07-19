import SwiftUI

/// Grid of top-level Spaces shown on the Home page.
/// Hides entirely when the user has no Spaces.
struct HomeSpacesSection: View {
    var onSelectSpace: (UUID) -> Void
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        let spaces = spaceStore.topLevelSpaces
        if !spaces.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardSectionHeader(icon: "folder.fill", title: "Your Spaces")
                    Spacer()
                    if spaces.count > 6 {
                        // B20: Disabled until spaces navigation is wired
                        Button {} label: {
                            Text("View All")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppThemeConstants.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                        .help("Coming soon")
                        .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 24)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(Array(spaces.prefix(6))) { space in
                        spaceCard(space)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Space Card

    private func spaceCard(_ space: Space) -> some View {
        let allIDs = [space.id] + spaceStore.allDescendantIDs(of: space.id)
        let docCount = allIDs.reduce(0) { $0 + documentStore.documents(inSpace: $1).count }
        let meetingCount = allIDs.reduce(0) { $0 + meetingStore.meetings(inSpace: $1).count }
        let recentCount = recentItemCount(for: space.id)

        return HomeCardShell {
            onSelectSpace(space.id)
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: space.icon ?? "folder")
                        .font(.title3)
                        .foregroundStyle(AppThemeConstants.accent)
                    Spacer()
                    if recentCount > 0 {
                        Text("\(recentCount) new")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppThemeConstants.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                AppThemeConstants.success.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                }

                Text(space.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(space.summary ?? itemCountText(docCount: docCount, meetingCount: meetingCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if docCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                            Text("\(docCount)")
                        }
                    }
                    if meetingCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "waveform")
                            Text("\(meetingCount)")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        } contextMenu: {
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func itemCountText(docCount: Int, meetingCount: Int) -> String {
        var parts: [String] = []
        if docCount > 0 {
            parts.append("\(docCount) doc\(docCount == 1 ? "" : "s")")
        }
        if meetingCount > 0 {
            parts.append("\(meetingCount) meeting\(meetingCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Empty space" : parts.joined(separator: ", ")
    }

    private func recentItemCount(for spaceID: UUID) -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let allIDs = [spaceID] + spaceStore.allDescendantIDs(of: spaceID)
        let docs = allIDs.reduce(0) { $0 + documentStore.documents(inSpace: $1).filter { $0.modifiedAt >= weekAgo }.count }
        let meetings = allIDs.reduce(0) { $0 + meetingStore.meetings(inSpace: $1).filter { $0.modifiedAt >= weekAgo }.count }
        return docs + meetings
    }
}
