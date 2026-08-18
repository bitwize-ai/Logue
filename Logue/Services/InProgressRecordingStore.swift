import Foundation
import os.log

/// Where a recording's audio lives while it is still being recorded.
///
/// Not the temporary directory. A session's audio used to be written there with a delete-on-reboot
/// resource value, which is exactly right for audio that will be moved into place when recording
/// stops, and exactly wrong for audio that has to survive the app not getting that far.
///
/// A directory left behind here *is* the signal that a session did not stop cleanly, so it is
/// created when recording starts and removed when recording stops.
enum InProgressRecordingStore {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "InProgressRecording")

    static func rootDirectory() throws -> URL {
        // `.first` rather than `[0]`: the array can be empty on edge-case system configurations.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let root = support
            .appending(component: AppConstants.appName)
            .appending(component: "InProgress")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func directory(for meetingID: UUID) throws -> URL {
        let directory = try rootDirectory().appending(component: meetingID.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Meetings with in-progress state left behind — sessions that did not stop cleanly.
    static func pendingMeetingIDs() -> [UUID] {
        do {
            let root = try rootDirectory()
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            return entries.compactMap { UUID(uuidString: $0.lastPathComponent) }
        } catch {
            logger.error("Could not list in-progress recordings: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Removes a session's working directory.
    ///
    /// `removeItem` rather than `trashItem`, which the rest of the app uses. This is correct here
    /// and only here: these are the app's own working files, never something the user can see or
    /// has named, and filling their Trash with them would be the surprising behaviour.
    static func clear(meetingID: UUID) {
        do {
            let directory = try rootDirectory().appending(component: meetingID.uuidString)
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.error("Could not clear in-progress recording: \(error.localizedDescription, privacy: .public)")
        }
    }
}
