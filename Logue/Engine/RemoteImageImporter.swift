import CryptoKit
import Foundation
import OSLog

/// Finds remote image references in pasted markdown so they can be copied into
/// local storage, keeping a document readable offline and after the source moves.
///
/// URLs come from arbitrary web pages, so detection is a security boundary. Only
/// `http`/`https` is accepted, and hosts on the local machine or a private network
/// are refused so a crafted paste cannot make the app probe an internal service.
enum RemoteImageImporter {
    /// One remote image reference found in markdown.
    struct Reference: Equatable, Sendable {
        let url: URL
        let altText: String
        /// UTF-16 range of the whole `![alt](url)` reference.
        let range: NSRange
    }

    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "RemoteImageImport")

    /// `![alt](url)` — alt may be empty, the URL may not contain spaces or parens.
    private static let pattern = "!\\[([^\\]\n]*)\\]\\(([^)\\s]+)\\)"

    private static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    // MARK: - Detection

    /// Remote image references worth importing, in document order.
    static func remoteImages(in markdown: String) -> [Reference] {
        guard !markdown.isEmpty, let regex else { return [] }

        let nsText = markdown as NSString
        let full = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: markdown, range: full).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let altText = nsText.substring(with: match.range(at: 1))
            let rawURL = nsText.substring(with: match.range(at: 2))

            guard let url = URL(string: rawURL), isImportable(url) else { return nil }
            return Reference(url: url, altText: altText, range: match.range)
        }
    }

    /// Whether the app is willing to fetch this URL.
    static func isImportable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return !isLocalOrPrivate(host: host)
    }

    // MARK: - Rewriting

    /// Replaces imported references with their local paths.
    ///
    /// References missing from `replacing` are left pointing at their remote URL — a
    /// failed import should leave a working remote image, not a broken local one.
    static func rewriting(markdown: String, replacing localPaths: [URL: String]) -> String {
        guard !localPaths.isEmpty else { return markdown }

        var result = markdown
        // Back-to-front so earlier ranges stay valid as lengths change.
        for reference in remoteImages(in: markdown).reversed() {
            guard let localPath = localPaths[reference.url] else { continue }
            let rebuilt = "![\(reference.altText)](\(localPath))"
            result = (result as NSString).replacingCharacters(in: reference.range, with: rebuilt)
        }
        return result
    }

    // MARK: - Filenames

    /// A safe, stable, collision-resistant filename for a remote image.
    ///
    /// The URL's own path is never used directly: a crafted path could otherwise
    /// escape the attachments directory. The name is derived from a hash of the full
    /// URL, so the same image imports to the same file and two images sharing a
    /// basename on different hosts do not collide.
    static func suggestedFilename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hash = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16)

        let rawExtension = url.pathExtension.lowercased()
        let allowed = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        let ext = allowed.contains(rawExtension) ? rawExtension : "png"

        return "\(hash).\(ext)"
    }

    // MARK: - Private

    /// Hosts that must never be fetched: the local machine, link-local metadata
    /// endpoints, private ranges, and mDNS names.
    private static func isLocalOrPrivate(host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        // IPv6 loopback and unique-local, with or without brackets.
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "::1" || bare.hasPrefix("fc") || bare.hasPrefix("fd") || bare.hasPrefix("fe80") {
            return true
        }

        let parts = bare.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (0, _):
            return true
        case (192, 168):
            return true
        case (169, 254): // link-local, includes cloud metadata endpoints
            return true
        case let (172, second) where (16 ... 31).contains(second):
            return true
        default:
            return false
        }
    }
}
