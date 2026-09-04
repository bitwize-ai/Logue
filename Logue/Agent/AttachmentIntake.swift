import AppKit
import UniformTypeIdentifiers

/// Getting files into a message, from wherever the message is being written.
///
/// Extracted from `InputBarView`, where it was `private` and therefore unreachable from the
/// Command Center island — which is why the island has never accepted an attachment at all,
/// despite `AgentCoordinator.send` taking them since the two surfaces were joined.
///
/// The rules here are the ones that were easy to get subtly different in a second copy:
/// which types are offered, and what happens when the same file arrives twice.
@MainActor
enum AttachmentIntake {
    /// What the picker offers, and by extension what a surface claims to accept.
    ///
    /// Drops are deliberately *not* filtered against this. A file manager hands over a URL
    /// with no type negotiation, and `TempAttachmentLoader` already refuses what it cannot
    /// read — filtering twice, in two places, is how a file that loads fine starts being
    /// rejected on one surface and not the other.
    static let acceptedTypes: [UTType] = [
        .pdf, .plainText, .text, .image,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? .data,
    ]

    /// Adds `incoming` to `existing`, skipping anything already there.
    ///
    /// De-duped by display name rather than by URL: dragging the same file twice is a slip,
    /// not a request for two copies, and the two drags can carry different URLs for one file
    /// — a security-scoped copy the second time, for instance.
    static func merging(
        _ incoming: [TempAttachment],
        into existing: [TempAttachment]
    ) -> [TempAttachment] {
        var result = existing
        for attachment in incoming
            where !result.contains(where: { $0.displayName == attachment.displayName })
        {
            result.append(attachment)
        }
        return result
    }

    /// Loads `urls` into attachments, in the order given.
    ///
    /// The `if let` is a contract rather than a filter: `TempAttachmentLoader.load` returns
    /// an attachment for every URL today — an unreadable file becomes a chip carrying no
    /// text rather than being dropped. This is written to tolerate a `nil` anyway, because
    /// the alternative reading (fail the batch) is the wrong one: attaching four files and
    /// getting none because one was a broken alias is worse than attaching three.
    ///
    /// `AttachmentIntakeTests` pins the ordering and the every-URL-yields-one contract, so
    /// changing the loader to drop files is a decision that has to be made deliberately.
    static func load(urls: [URL]) async -> [TempAttachment] {
        var loaded: [TempAttachment] = []
        for url in urls {
            if let attachment = await TempAttachmentLoader.load(from: url) {
                loaded.append(attachment)
            }
        }
        return loaded
    }

    /// Presents the open panel and returns what the user picked, or nothing if they cancelled.
    static func pickFiles() async -> [TempAttachment] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = acceptedTypes
        panel.prompt = "Attach"
        panel.message = "Select files to attach to your message"

        let urls: [URL] = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }
        }
        return await load(urls: urls)
    }

    /// Pulls file URLs out of a drop.
    ///
    /// `NSItemProvider` hands back either a `URL` or its `Data` representation depending on
    /// where the drag came from, so both are unpacked. Anything else is not a file.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                            switch item {
                            case let url as URL:
                                continuation.resume(returning: url)
                            case let data as Data:
                                continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                            default:
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
            }
            var found: [URL] = []
            for await url in group {
                if let url {
                    found.append(url)
                }
            }
            return found
        }
    }
}
