import SwiftUI

/// Shows the current document's place in the wikilink graph: what it links out to,
/// what links back to it, and any `[[targets]]` that match nothing.
///
/// The graph is rebuilt from the stores on appear and whenever the body changes.
/// `LinkIndex` is a cheap immutable snapshot, so rebuilding is simpler and safer
/// than tracking incremental invalidation.
struct LinksPanelView: View {
    let documentID: UUID
    /// Body text of the current document. Drives a rebuild when it changes.
    /// Named `documentBody` because `body` would collide with `View.body`.
    let documentBody: String

    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var index: LinkIndex?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let index {
                    let neighborhood = Neighborhood(index: index, sourceID: documentID)

                    if neighborhood.isEmpty, index.brokenTargets(from: documentID).isEmpty {
                        Text("No links yet. Type [[ in the document to link to another document or meeting.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(neighborhood.groups) { group in
                        linkSection(
                            title: group.title,
                            systemImage: group.symbolName,
                            ids: group.itemIDs,
                            index: index
                        )
                    }

                    brokenSection(targets: index.brokenTargets(from: documentID))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(16)
        }
        .task(id: rebuildKey) { await rebuild() }
    }

    /// What makes the panel stale.
    ///
    /// Body *length* was the trigger before, which misses any edit that preserves it — retyping
    /// `[[Notes]]` as `[[Ideas]]` left the key identical, so the panel went on listing `Notes` as an
    /// outgoing link and never showed `Ideas`. Hashing the link targets rather than the prose also
    /// means ordinary typing does not rebuild the graph at all.
    ///
    /// The document counts are here because the index is a snapshot of the whole library: another
    /// document being created, renamed or trashed while the panel is open changes what resolves, and
    /// watching only the current document left phantom backlinks on screen.
    private var rebuildKey: String {
        let targets = WikiLinkParser.uniqueTargets(in: documentBody).sorted().joined(separator: "\u{1F}")
        return [
            documentID.uuidString,
            String(targets.hashValue),
            String(documentStore.documents.count),
            String(meetingStore.meetings.count),
        ].joined(separator: "-")
    }

    /// Builds off the main actor.
    ///
    /// `LinkIndex.build` runs a regular expression over every document body and every meeting
    /// summary. The editor commits its body on a 300 ms debounce, so with this panel open the whole
    /// library was re-scanned on the main thread every 300 ms of typing.
    private func rebuild() async {
        let documents = documentStore.documents
        let meetings = meetingStore.meetings

        index = await Task.detached(priority: .userInitiated) {
            LinkIndex.build(documents: documents, meetings: meetings)
        }.value
    }

    // MARK: - Sections

    private func linkSection(
        title: String,
        systemImage: String,
        ids: [UUID],
        index: LinkIndex
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LinksSectionHeader(title: title, systemImage: systemImage, itemCount: ids.count)

            ForEach(ids, id: \.self) { id in
                LinkRow(
                    title: index.title(of: id) ?? "Untitled",
                    kind: index.kind(of: id),
                    action: { open(id: id, kind: index.kind(of: id)) }
                )
            }
        }
    }

    @ViewBuilder
    private func brokenSection(targets: [String]) -> some View {
        if !targets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                LinksSectionHeader(
                    title: "Unresolved",
                    systemImage: "exclamationmark.triangle",
                    itemCount: targets.count
                )

                Text("These links point at titles that do not exist.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ForEach(targets, id: \.self) { target in
                    Text(target)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }
            }
        }
    }

    // MARK: - Navigation

    /// Goes through `ContentNavigator` rather than setting selection directly, so a
    /// jump from this panel records back history like a link click does.
    private func open(id: UUID, kind: LinkIndex.Kind?) {
        switch kind {
        case .document:
            ContentNavigator.open(.document(id: id))
        case .meeting:
            ContentNavigator.open(.meeting(id: id))
        case nil:
            break
        }
    }
}

// MARK: - Rows

private struct LinksSectionHeader: View {
    let title: String
    let systemImage: String
    /// Named `itemCount` rather than `count` so SwiftLint's `empty_count` rule
    /// does not read `count > 0` as a collection-emptiness check.
    let itemCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if itemCount > 0 {
                Text("\(itemCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct LinkRow: View {
    let title: String
    let kind: LinkIndex.Kind?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: kind == .meeting ? "waveform" : "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppThemeConstants.accent.opacity(isHovered ? 0.12 : 0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open \(title)")
    }
}
