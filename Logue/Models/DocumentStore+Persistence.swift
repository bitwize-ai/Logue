import Foundation
import os.log

/// Writing documents to encrypted storage.
///
/// Encrypted files are written in **both** modes, not only when markdown storage is off. In
/// markdown mode they hold what the folder cannot: trashed documents, which are kept out of it
/// on purpose, and documents whose file could not be written. `DocumentStorage.save` returning
/// `false` is the signal for both.
@MainActor
extension DocumentStore {
    /// Writes documents to encrypted storage, one file each. Cancels any bulk save in flight.
    func writeEncrypted(_ documents: [WritingDocument]) {
        guard !documents.isEmpty else { return }
        bulkSaveTask?.cancel()
        let snapshot = documents
        let dir = documentsDirectory
        bulkSaveTask = Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for doc in snapshot {
                    guard !Task.isCancelled else { return }
                    let url = dir.appendingPathComponent("\(doc.id.uuidString).json")
                    let data = try EncryptionManager.encryptCodable(doc)
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                guard !Task.isCancelled else { return }
                Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                    .error("Failed to save documents: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
