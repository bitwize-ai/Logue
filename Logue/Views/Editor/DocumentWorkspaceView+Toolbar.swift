import SwiftUI

// MARK: - Toolbar

extension DocumentWorkspaceView {
    @ToolbarContentBuilder
    func documentToolbarContent(doc: WritingDocument) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                let doc = store.createDocument()
                store.selectedDocumentID = doc.id
            } label: {
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("New Document")
            }
            .help("New Document")
        }

        ToolbarItem(placement: .primaryAction) {
            moreOptionsMenu(doc: doc)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                focusState.enter()
            } label: {
                Image(systemName: "rectangle.center.inset.filled")
            }
            .help("Enter Focus Mode (⇧⌘F)")
            .accessibilityLabel("Enter Focus Mode")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(isSidebarCollapsed ? "Show Tools Sidebar" : "Hide Tools Sidebar")
        }
    }

    /// Minimal toolbar shown in Focus Mode — only an exit button.
    @ToolbarContentBuilder
    var focusModeToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                focusState.exit()
            } label: {
                Label("Exit Focus", systemImage: "xmark.circle")
            }
            .help("Exit Focus Mode (Esc)")
            .accessibilityLabel("Exit Focus Mode")
        }
    }

    @ViewBuilder
    func moreMenuItems(doc: WritingDocument) -> some View {
        Button("Undo") {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        }
        Button("Redo") {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        }
        Toggle("Word Count", isOn: $showWordCount)
        Divider()
        Button {
            titleGenerationTask?.cancel()
            titleGenerationTask = Task {
                await store.regenerateAITitle(for: doc.id)
            }
        } label: {
            Label("Generate Title", systemImage: "sparkles")
        }
        .disabled(doc.body.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || LLMEngineStatus.shared.isBusy)
        Button {
            renameText = doc.title
            showRenameAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            showTagPopover = true
        } label: {
            Label("Add Tag", systemImage: "tag")
        }
        Button {
            showSaveAsTemplate = true
        } label: {
            Label("Save as Template", systemImage: "doc.on.doc")
        }
        Menu("Export") {
            Button {
                PDFExportService.export(document: doc)
            } label: {
                Label("Export as PDF", systemImage: "arrow.down.doc")
            }
            Button {
                exportAsMarkdown(doc: doc)
            } label: {
                Label("Export as Markdown", systemImage: "doc.plaintext")
            }
        }
        Divider()
        Button(role: .destructive) {
            store.deleteDocument(id: doc.id)
        } label: {
            Label("Delete Document", systemImage: "trash")
        }
    }

    func moreOptionsMenu(doc: WritingDocument) -> some View {
        Menu {
            moreMenuItems(doc: doc)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("More options")
        .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
            tagPopoverContent(doc: doc)
        }
        .alert("Rename Document", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                store.renameDocument(id: doc.id, newTitle: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
