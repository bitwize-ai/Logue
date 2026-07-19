import AppKit
import Foundation
import os.log

/// On-disk favicon cache for source URLs (web search results, fetched pages).
/// Mostly used by the Sources Panel and any place that renders a tiny domain
/// icon next to a URL.
///
/// Layout: `~/Library/Caches/com.bitwize.logue/favicons/<host>.png`. Hosts
/// are reused across schemes so `https://example.com` and `http://example.com`
/// share the same icon. We don't expire entries — favicons rarely change and
/// the user rarely accumulates more than a few hundred unique hosts; the
/// cache directory is naturally cleared by macOS during low-storage events.
@MainActor
@Observable
final class FaviconCache {
    static let shared = FaviconCache()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "FaviconCache")
    private var inMemory: [String: NSImage] = [:]
    /// Hosts we've already attempted to fetch this session, so a 404 doesn't
    /// retry on every render. Cleared on app relaunch.
    private var attempted: Set<String> = []

    private init() {
        do {
            try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create favicon cache directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Resolve a favicon for the URL synchronously from the in-memory cache,
    /// or `nil` if it isn't cached yet. SwiftUI views call this on render and
    /// `prefetch(for:)` to kick off the async fetch.
    func cached(for url: URL) -> NSImage? {
        guard let host = url.host else { return nil }
        if let img = inMemory[host] {
            return img
        }
        let path = Self.cacheDirectory.appending(path: "\(host).png")
        if let data = try? Data(contentsOf: path), let img = NSImage(data: data) {
            inMemory[host] = img
            return img
        }
        return nil
    }

    /// Kick off a background fetch if we don't have one cached yet. Idempotent.
    func prefetch(for url: URL) {
        guard let host = url.host, inMemory[host] == nil, !attempted.contains(host) else { return }
        attempted.insert(host)
        Task.detached(priority: .background) { [weak self] in
            await self?.fetch(host: host, sourceScheme: url.scheme ?? "https")
        }
    }

    private func fetch(host: String, sourceScheme: String) async {
        // Try the standard `/favicon.ico` first, then Google's free favicon
        // service as a fallback for domains that don't serve one.
        let candidates: [URL] = [
            URL(string: "\(sourceScheme)://\(host)/favicon.ico"),
            URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)"),
        ].compactMap { $0 }

        for candidate in candidates {
            do {
                var request = URLRequest(url: candidate)
                request.timeoutInterval = 4
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                    continue
                }
                guard let image = NSImage(data: data) else { continue }
                let path = Self.cacheDirectory.appending(path: "\(host).png")
                if let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:])
                {
                    try? png.write(to: path)
                }
                await MainActor.run { self.inMemory[host] = image }
                return
            } catch {
                continue
            }
        }
        // Don't error-log on miss — favicon absence is not noteworthy.
    }

    private static let cacheDirectory: URL = {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        return base
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "favicons", directoryHint: .isDirectory)
    }()
}
