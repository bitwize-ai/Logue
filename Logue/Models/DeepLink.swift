import Foundation

/// A `logue://` deep link to an item in the library.
///
/// Links arrive from outside the app (Finder, browsers, other apps), so parsing
/// treats the URL as untrusted input: anything not matching exactly one known
/// host plus one well-formed UUID path component resolves to `nil` rather than a
/// best guess.
enum DeepLink: Equatable, Sendable {
    case document(id: UUID)
    case meeting(id: UUID)
    case space(id: UUID)

    static let scheme = "logue"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased()
        else { return nil }

        // Exactly one component — reject empty, extra, and traversal paths alike.
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1,
              let identifier = UUID(uuidString: components[0])
        else { return nil }

        switch host {
        case Host.document: self = .document(id: identifier)
        case Host.meeting: self = .meeting(id: identifier)
        case Host.space: self = .space(id: identifier)
        default: return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = host
        components.path = "/\(identifier.uuidString)"
        // Unreachable in practice: scheme and host are constants and a UUID string
        // contains only URL-safe characters.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    var identifier: UUID {
        switch self {
        case let .document(id), let .meeting(id), let .space(id): id
        }
    }

    private var host: String {
        switch self {
        case .document: Host.document
        case .meeting: Host.meeting
        case .space: Host.space
        }
    }

    private enum Host {
        static let document = "document"
        static let meeting = "meeting"
        static let space = "space"
    }

    // MARK: - Notification Bridging

    /// Typed `userInfo` keys — never string literals at the call site.
    enum UserInfoKey {
        static let identifier = "deepLinkIdentifier"
    }

    var notificationName: Notification.Name {
        switch self {
        case .document: .deepLinkOpenDocument
        case .meeting: .deepLinkOpenMeeting
        case .space: .deepLinkOpenSpace
        }
    }

    var notificationPayload: [String: Any] {
        [UserInfoKey.identifier: identifier]
    }
}

extension Notification.Name {
    static let deepLinkOpenDocument = Notification.Name("deepLinkOpenDocument")
    static let deepLinkOpenMeeting = Notification.Name("deepLinkOpenMeeting")
    static let deepLinkOpenSpace = Notification.Name("deepLinkOpenSpace")
}

// MARK: - Router

/// Turns an incoming URL into a navigation notification.
///
/// Kept separate from `DeepLink` so parsing stays free of side effects and can be
/// tested without observing NotificationCenter.
enum DeepLinkRouter {
    /// Returns `true` when the URL was a recognised deep link and was dispatched.
    @discardableResult
    static func route(url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        NotificationCenter.default.post(
            name: link.notificationName,
            object: nil,
            userInfo: link.notificationPayload
        )
        return true
    }
}
