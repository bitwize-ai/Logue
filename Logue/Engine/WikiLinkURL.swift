import Foundation

/// The URL form of a wikilink, used as an `NSAttributedString.link` value so AppKit
/// handles hover and click for us.
///
/// Deliberately separate from `DeepLink`: that models external `logue://` entry
/// points keyed by UUID, whereas a wikilink is an internal, unresolved *title*.
/// Conflating them would mean inventing a UUID at styling time, when the styler has
/// no access to the stores.
enum WikiLinkURL {
    static let scheme = "logue-wikilink"

    /// Encodes a target as a URL. Returns `nil` for a target that cannot be encoded.
    static func url(for target: String) -> URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = "/\(trimmed)"
        return components.url
    }

    /// Extracts the target from a URL, or `nil` when it is not a wikilink URL.
    static func target(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        let target = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
