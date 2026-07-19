import AppKit
import Foundation
import MLXLMCommon

// MARK: - GetConfirmationTool

/// Mid-loop yes/no dialog. Use when the agent needs an explicit user OK
/// before continuing (e.g. "I'm about to delete 7 files — proceed?"). The
/// dialog is an `NSAlert` modal sheet on the active window.
///
/// `.regular` clearance — the dialog itself IS the consent surface, so
/// wrapping the call in another approval card would be redundant.
struct GetConfirmationTool: AgentTool {
    let name = "get_confirmation"
    let description = """
    Show the user a yes/no confirmation dialog. Returns "yes" or "no" based \
    on the user's choice. Use sparingly — only when the next step really needs \
    a deliberate green-light (irreversible side effects, costly compute, etc.).
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Short headline (e.g. \"Delete 7 files?\")"),
                "message": AgentToolSpec.stringParam("Body text explaining what's about to happen (optional)"),
                "confirm_label": AgentToolSpec.stringParam("Label on the confirm button (default \"Yes\")"),
                "cancel_label": AgentToolSpec.stringParam("Label on the cancel button (default \"No\")"),
            ],
            required: ["title"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let title = (arguments["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else {
            throw AgentToolError.missingParameter("title")
        }
        let message = (arguments["message"] as? String) ?? ""
        let confirmLabel = (arguments["confirm_label"] as? String) ?? "Yes"
        let cancelLabel = (arguments["cancel_label"] as? String) ?? "No"

        let confirmed: Bool = await MainActor.run {
            let alert = NSAlert()
            alert.messageText = String(title.prefix(120))
            alert.informativeText = String(message.prefix(500))
            alert.alertStyle = .informational
            alert.addButton(withTitle: String(confirmLabel.prefix(40)))
            alert.addButton(withTitle: String(cancelLabel.prefix(40)))
            return alert.runModal() == .alertFirstButtonReturn
        }
        return confirmed ? "yes" : "no"
    }
}

// MARK: - GetTextInputTool

/// Mid-loop free-text dialog. Use when the agent needs the user to type a
/// value it can't infer (e.g. "What date should I use for the report?").
///
/// `.regular` clearance — same reasoning as `get_confirmation`.
struct GetTextInputTool: AgentTool {
    let name = "get_text_input"
    let description = """
    Show the user a text input dialog and return what they type. Useful when \
    you need a value the user hasn't supplied (a date, a person's name, a file \
    path) and asking in chat would be slower. Returns the entered text, or \
    "(cancelled)" if the user dismissed the dialog.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Short headline (e.g. \"What email address?\")"),
                "message": AgentToolSpec.stringParam("Body text describing what to enter (optional)"),
                "default_value": AgentToolSpec.stringParam("Pre-filled text in the input field (optional)"),
                "placeholder": AgentToolSpec.stringParam("Greyed-out hint inside the field (optional)"),
            ],
            required: ["title"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let title = (arguments["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else {
            throw AgentToolError.missingParameter("title")
        }
        let message = (arguments["message"] as? String) ?? ""
        let defaultValue = (arguments["default_value"] as? String) ?? ""
        let placeholder = (arguments["placeholder"] as? String) ?? ""

        let result: String? = await MainActor.run {
            let alert = NSAlert()
            alert.messageText = String(title.prefix(120))
            alert.informativeText = String(message.prefix(500))
            alert.alertStyle = .informational

            // 280pt-wide single-line text field — wide enough for an email,
            // a date string, or a short answer.
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = String(defaultValue.prefix(500))
            field.placeholderString = String(placeholder.prefix(120))
            alert.accessoryView = field

            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            // Return-key submits the dialog by activating the OK button.
            field.becomeFirstResponder()

            let response = alert.runModal()
            return response == .alertFirstButtonReturn ? field.stringValue : nil
        }
        guard let result else { return "(cancelled)" }
        return String(result.prefix(2000))
    }
}

// MARK: - GetUserSelectionTool

/// Show the user a single-choice dropdown of pre-defined options and return
/// the chosen value. Use when the agent has a closed set of valid answers
/// (a list of categories, a list of files, a yes/no/maybe etc.) — picking
/// from a popup is faster than typing.
///
/// `.regular` clearance — the dialog itself is the consent surface.
struct GetUserSelectionTool: AgentTool {
    let name = "get_user_selection"
    let description = """
    Show the user a popup-button dialog with a list of options and return the \
    one they pick. Use when the answer is constrained to a small set of \
    pre-defined choices (categories, file names, statuses, etc.). Returns \
    the picked option, or "(cancelled)" if the user dismissed the dialog.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Short headline (e.g. \"Which space?\")"),
                "message": AgentToolSpec.stringParam("Body text explaining the choice (optional)"),
                "options": AgentToolSpec.stringParam("Newline- or pipe-separated list of options (max 20)"),
                "default_index": AgentToolSpec.intParam("Index of the option to pre-select (0-based)"),
            ],
            required: ["title", "options"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let title = (arguments["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else {
            throw AgentToolError.missingParameter("title")
        }
        guard let rawOptions = arguments["options"] as? String, !rawOptions.isEmpty else {
            throw AgentToolError.missingParameter("options")
        }
        let separators = CharacterSet(charactersIn: "\n|")
        let options = rawOptions
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)
        guard !options.isEmpty else {
            throw AgentToolError.invalidParameter("options", "Must include at least one option")
        }

        let message = (arguments["message"] as? String) ?? ""
        let defaultIndex = max(0, min((arguments["default_index"] as? Int) ?? 0, options.count - 1))

        let result: String? = await MainActor.run {
            let alert = NSAlert()
            alert.messageText = String(title.prefix(120))
            alert.informativeText = String(message.prefix(500))
            alert.alertStyle = .informational

            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
            for option in options {
                popup.addItem(withTitle: String(option.prefix(120)))
            }
            popup.selectItem(at: defaultIndex)
            alert.accessoryView = popup

            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            return response == .alertFirstButtonReturn ? popup.titleOfSelectedItem : nil
        }

        return result ?? "(cancelled)"
    }
}
