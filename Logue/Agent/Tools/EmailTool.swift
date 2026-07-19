import AppKit
import Foundation
import MLXLMCommon

// MARK: - DraftEmailTool

/// Opens a new email draft in the user's default mail client via `mailto:`.
/// Apple-native, sandbox-safe. `.sensitive` clearance because it triggers an
/// external-app side effect.
struct DraftEmailTool: AgentTool {
    let name = "draft_email"
    let description = """
    Opens a new email draft in the user's default mail client. Provide one or more \
    recipient email addresses, an optional subject, and an optional body. The user \
    sees and sends the email manually — you cannot send mail directly.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "to": AgentToolSpec.stringParam(
                    "Comma-separated recipient email addresses (e.g. \"alice@x.com, bob@y.com\")"
                ),
                "subject": AgentToolSpec.stringParam("Email subject (optional)"),
                "body": AgentToolSpec.stringParam("Email body (optional)"),
                "cc": AgentToolSpec.stringParam("Comma-separated CC addresses (optional)"),
                "bcc": AgentToolSpec.stringParam("Comma-separated BCC addresses (optional)"),
            ],
            required: ["to"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawTo = arguments["to"] as? String, !rawTo.isEmpty else {
            throw AgentToolError.missingParameter("to")
        }
        // Validate at least one recipient looks like an email — guard against
        // a malformed model output dropping a non-email string into mailto:
        // (which would silently open Mail with no recipient).
        let recipients = rawTo
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.looksLikeEmail($0) }
        guard !recipients.isEmpty else {
            throw AgentToolError.invalidParameter("to", "No valid email addresses found")
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.joined(separator: ",")

        var query: [URLQueryItem] = []
        if let subject = (arguments["subject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            query.append(URLQueryItem(name: "subject", value: subject))
        }
        if let body = (arguments["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            query.append(URLQueryItem(name: "body", value: body))
        }
        if let cc = (arguments["cc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !cc.isEmpty {
            query.append(URLQueryItem(name: "cc", value: cc))
        }
        if let bcc = (arguments["bcc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !bcc.isEmpty {
            query.append(URLQueryItem(name: "bcc", value: bcc))
        }
        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw AgentToolError.executionFailed("Could not build mailto URL")
        }

        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else {
            throw AgentToolError.executionFailed("Could not open the default mail client")
        }
        return "Opened a new email draft to \(recipients.joined(separator: ", ")). The user will review and send it."
    }

    /// Cheap regex sanity check — not RFC-5322, but rules out the common
    /// failure mode where the model passes a name instead of an address.
    private static func looksLikeEmail(_ candidate: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return candidate.range(of: pattern, options: .regularExpression) != nil
    }
}
