import SwiftUI

// MARK: - Grid Cards & List Rows

extension SpaceContentPane {
    // MARK: - Space Grid Card

    func spaceGridCard(_ child: Space) -> some View {
        let docCount = documentStore.documents(inSpace: child.id).count
        let meetingCount = meetingStore.meetings(inSpace: child.id).count
        let titleIsLong = child.name.count > 30
        let descriptionLines = titleIsLong ? 3 : 4

        return HomeCardShell {
            navigateToSpace(child.id)
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: child.icon ?? "folder")
                        .font(.title3)
                        .foregroundStyle(AppThemeConstants.accent)
                    Spacer()
                }

                Text(child.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(child.summary ?? spaceItemCountText(docCount: docCount, meetingCount: meetingCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionLines)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                spaceGridCardFooter(child, docCount: docCount, meetingCount: meetingCount)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        } contextMenu: {
            spaceCardContextMenu(child)
        }
    }

    private func spaceGridCardFooter(_ child: Space, docCount: Int, meetingCount: Int) -> some View {
        HStack {
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
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            Text(child.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Document Grid Card

    func documentGridCard(_ doc: WritingDocument) -> some View {
        let titleIsLong = doc.title.count > 30
        let snippetLines = titleIsLong ? 3 : 4

        return HomeCardShell {
            documentStore.selectedDocumentID = doc.id
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                documentGridCardHeader(doc)

                Text(doc.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(doc.snippet.isEmpty ? "Empty document" : doc.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(snippetLines)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack {
                    Text("\(doc.wordCount)w")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        } contextMenu: {
            documentCardContextMenu(doc)
        }
    }

    private func documentGridCardHeader(_ doc: WritingDocument) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            if doc.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(AppThemeConstants.pinnedColor)
            }
        }
    }

    @ViewBuilder
    func documentCardContextMenu(_ doc: WritingDocument) -> some View {
        Button {
            documentStore.selectedDocumentID = doc.id
        } label: {
            Label("Open", systemImage: "doc.text")
        }
        Button {
            documentStore.togglePin(id: doc.id)
        } label: {
            Label(
                doc.isPinned ? "Unpin" : "Pin",
                systemImage: doc.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            renameText = doc.title
            renamingDocID = doc.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        moveToSpaceMenu(forDocument: doc)
        Button {
            PDFExportService.export(document: doc)
        } label: {
            Label("Export as PDF", systemImage: "arrow.down.doc")
        }
        Divider()
        Button(role: .destructive) {
            documentStore.deleteDocument(id: doc.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    // MARK: - Meeting Grid Card

    func meetingGridCard(_ meeting: MeetingNote) -> some View {
        let titleIsLong = meeting.title.count > 30
        let previewLines = titleIsLong ? 3 : 4

        return HomeCardShell {
            meetingStore.selectedMeetingID = meeting.id
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                meetingGridCardHeader(meeting)

                Text(meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let preview = meetingPreviewText(meeting) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(previewLines)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                meetingGridCardFooter(meeting)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        } contextMenu: {
            meetingCardContextMenu(meeting)
        }
    }

    private func meetingGridCardHeader(_ meeting: MeetingNote) -> some View {
        HStack {
            Image(systemName: meeting.recordingMode.iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            if meeting.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(AppThemeConstants.pinnedColor)
            }
        }
    }

    private func meetingGridCardFooter(_ meeting: MeetingNote) -> some View {
        HStack {
            HStack(spacing: 4) {
                if meeting.duration > 0 {
                    Text(meeting.formattedDuration)
                        .monospacedDigit()
                }
                if !meeting.actionItems.isEmpty {
                    let pending = meeting.actionItems.filter { !$0.isCompleted }.count
                    if pending > 0 {
                        if meeting.duration > 0 {
                            Text("\u{00B7}")
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "checklist")
                            Text("\(pending)")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(AppThemeConstants.actionBadgeColor)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    func meetingCardContextMenu(_ meeting: MeetingNote) -> some View {
        Button {
            meetingStore.selectedMeetingID = meeting.id
        } label: {
            Label("Open", systemImage: "waveform")
        }
        Button {
            meetingStore.togglePin(id: meeting.id)
        } label: {
            Label(
                meeting.isPinned ? "Unpin" : "Pin",
                systemImage: meeting.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            renameText = meeting.title
            renamingMeetingID = meeting.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            meetingStore.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        moveToSpaceMenu(forMeeting: meeting)
        Divider()
        Button(role: .destructive) {
            meetingStore.trashMeeting(id: meeting.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    // MARK: - Space Row

    func spaceRow(_ child: Space) -> some View {
        let docCount = documentStore.documents(inSpace: child.id).count
        let meetingCount = meetingStore.meetings(inSpace: child.id).count

        return HomeCardShell {
            navigateToSpace(child.id)
        } content: { _ in
            HStack(spacing: 12) {
                Image(systemName: child.icon ?? "folder")
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(child.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let summary = child.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(spaceItemCountText(docCount: docCount, meetingCount: meetingCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(child.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        } contextMenu: {
            spaceCardContextMenu(child)
        }
    }

    // MARK: - Document Row

    func documentRow(_ doc: WritingDocument) -> some View {
        HomeCardShell {
            documentStore.selectedDocumentID = doc.id
        } content: { _ in
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(doc.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if doc.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(AppThemeConstants.pinnedColor)
                        }
                    }
                    Text(doc.snippet.isEmpty ? "Empty document" : doc.snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        } contextMenu: {
            documentCardContextMenu(doc)
        }
    }

    // MARK: - Meeting Row

    func meetingRow(_ meeting: MeetingNote) -> some View {
        HomeCardShell {
            meetingStore.selectedMeetingID = meeting.id
        } content: { _ in
            HStack(spacing: 12) {
                Image(systemName: meeting.recordingMode.iconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(meeting.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if meeting.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(AppThemeConstants.pinnedColor)
                        }
                    }
                    HStack(spacing: 8) {
                        if meeting.duration > 0 {
                            Text(meeting.formattedDuration)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        } contextMenu: {
            meetingCardContextMenu(meeting)
        }
    }

    // MARK: - Helpers

    func meetingPreviewText(_ meeting: MeetingNote) -> String? {
        if let summary = meeting.summary {
            return summary
        }
        if !meeting.segments.isEmpty {
            return meeting.segments.prefix(8).map(\.text).joined(separator: " ")
        }
        return nil
    }

    func spaceItemCountText(docCount: Int, meetingCount: Int) -> String {
        var parts: [String] = []
        if docCount > 0 {
            parts.append("\(docCount) doc\(docCount == 1 ? "" : "s")")
        }
        if meetingCount > 0 {
            parts.append("\(meetingCount) meeting\(meetingCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Empty space" : parts.joined(separator: ", ")
    }

    func navigateToSpace(_ childID: UUID) {
        spaceStore.expandPath(to: childID)
        Task {
            try? await Task.sleep(for: AppConstants.Delays.sidebarNavigationYield)
            sidebarSelection = .space(childID)
        }
    }

    @ViewBuilder
    func spaceCardContextMenu(_ child: Space) -> some View {
        Button {
            navigateToSpace(child.id)
        } label: {
            Label("Open", systemImage: "folder")
        }

        Divider()

        Button {
            iconPickerSpaceID = child.id
        } label: {
            Label("Change Icon", systemImage: "star.square.on.square")
        }

        Button {
            renameText = child.name
            renamingSpaceID = child.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button {
            if let sub = spaceStore.createSpace(name: "New Space", parentID: child.id) {
                navigateToSpace(sub.id)
                renameText = ""
                renamingSpaceID = sub.id
            }
        } label: {
            Label("New Sub-Space", systemImage: "folder.badge.plus")
        }

        Button {
            let doc = documentStore.createDocument(inSpace: child.id)
            documentStore.selectedDocumentID = doc.id
        } label: {
            Label("New Document", systemImage: "doc.badge.plus")
        }

        Button {
            let meeting = meetingStore.createMeeting(
                title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                inSpace: child.id
            )
            meetingStore.selectedMeetingID = meeting.id
        } label: {
            Label("New Meeting", systemImage: "waveform.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            spaceStore.deleteSpace(id: child.id)
        } label: {
            Label("Delete Space", systemImage: "trash")
        }
    }

    // MARK: - Move to Space Menus

    @ViewBuilder
    func moveToSpaceMenu(forDocument doc: WritingDocument) -> some View {
        if !spaceStore.topLevelSpaces.isEmpty || doc.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: doc.spaceID) { newSpaceID in
                    documentStore.moveDocument(id: doc.id, toSpace: newSpaceID)
                }
            }
        }
    }

    @ViewBuilder
    func moveToSpaceMenu(forMeeting meeting: MeetingNote) -> some View {
        if !spaceStore.topLevelSpaces.isEmpty || meeting.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: meeting.spaceID) { newSpaceID in
                    meetingStore.moveMeeting(id: meeting.id, toSpace: newSpaceID)
                }
            }
        }
    }

    // MARK: - Drag & Drop

    func handleDrop(_ items: [WorkspaceDragItem], intoSpace targetSpaceID: UUID) -> Bool {
        var handled = false
        for item in items {
            switch item.type {
            case .document:
                documentStore.moveDocument(id: item.id, toSpace: targetSpaceID)
                handled = true
            case .meeting:
                meetingStore.moveMeeting(id: item.id, toSpace: targetSpaceID)
                handled = true
            case .space:
                spaceStore.moveSpace(id: item.id, toParent: targetSpaceID)
                handled = true
            }
        }
        return handled
    }
}
