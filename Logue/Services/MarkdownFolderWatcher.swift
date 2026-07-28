import Foundation
import OSLog

/// Watches `~/Logue` for changes made outside the app.
///
/// FSEvents rather than a `DispatchSource` file descriptor: the latter reports only the one
/// directory it was opened on, and this folder is a tree the user is invited to reorganise.
///
/// Events are coalesced twice — once by FSEvents' own latency and once by a debounce here —
/// because another editor may write a file in several chunks, and a scan that lands between
/// two of them would read a half-written document.
///
/// `@unchecked Sendable`: all mutable state is confined to `queue`, the serial queue the
/// FSEvents stream is scheduled on, and the only thing crossing threads is the callback,
/// which hops to the main actor.
final class MarkdownFolderWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MarkdownFolderWatcher")
    private let queue = DispatchQueue(label: "com.bitwize.logue.markdown-folder-watcher")

    private var stream: FSEventStreamRef?
    private var pendingScan: DispatchWorkItem?

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        // Not `stop()`: that hops onto `queue`, and a deinit must not outlive itself waiting
        // for another thread.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [self] in
            guard stream == nil else { return }
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.info("Not watching: the folder does not exist yet")
                return
            }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagIgnoreSelf
            )

            guard let created = FSEventStreamCreate(
                nil,
                eventCallback,
                &context,
                [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.coalescingLatency,
                flags
            )
            else {
                logger.error("Could not create a filesystem event stream for the documents folder")
                return
            }

            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
            logger.info("Watching the documents folder for outside changes")
        }
    }

    func stop() {
        queue.async { [self] in
            pendingScan?.cancel()
            pendingScan = nil
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    // MARK: - Events

    /// FSEvents' own coalescing window. Deliberately shorter than the debounce below, which
    /// does the real waiting — a long latency here would also delay the first event.
    private static let coalescingLatency: CFTimeInterval = 0.2

    /// Called on `queue` for every batch of events.
    fileprivate func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingScan = nil
            self?.onChange()
        }
        pendingScan = work
        queue.asyncAfter(
            deadline: .now() + AppConstants.Delays.folderScanDebounceSeconds, execute: work
        )
    }
}

/// Top-level rather than a closure property: `FSEventStreamCallback` is a C function pointer
/// and cannot capture context, which is what the `info` pointer is for.
private func eventCallback(
    _: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _: Int,
    _: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    // Unretained to match `passUnretained` above: the watcher owns the stream, so the stream
    // must not own the watcher.
    Unmanaged<MarkdownFolderWatcher>.fromOpaque(info).takeUnretainedValue().scheduleScan()
}
