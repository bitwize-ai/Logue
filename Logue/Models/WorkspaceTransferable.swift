import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Lightweight drag payload for moving items within the workspace.
struct WorkspaceDragItem: Codable, Transferable {
    enum ItemType: String, Codable {
        case document
        case meeting
        case space
    }

    let id: UUID
    let type: ItemType

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workspaceDragItem)
    }
}

extension UTType {
    static let workspaceDragItem = UTType(exportedAs: "com.bitwize.logue.workspace-drag-item")
}

extension WorkspaceDragItem {
    /// Creates an NSItemProvider for use with `.onDrag`, which doesn't
    /// intercept click-to-select in List the way `.draggable()` does.
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let data = try? JSONEncoder().encode(self)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.workspaceDragItem.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
