import Foundation

/// Turning the id in a tool call into the name of the thing it points at.
///
/// The other half of `ToolApprovalPrompt`: that file decides the wording and which argument
/// holds the target, and this is the part that has to touch the stores. Split so the wording
/// stays testable without them.
///
/// Reminders and calendar events are deliberately not resolved. Both live in EventKit behind
/// a permission the user may not have granted, and reaching for one while an approval card is
/// on screen would either block the main actor or prompt for access as a side effect of
/// *drawing* — neither of which is acceptable in a card whose whole job is to be trustworthy.
/// They fall back to the action alone, which is honest: "Delete" with nothing after it says
/// we do not know the name, rather than showing a UUID that says nothing at all.
@MainActor
enum ToolApprovalTargetResolver {
    static func name(for reference: ToolApprovalPrompt.Reference) -> String? {
        switch reference.kind {
        case .document:
            DocumentStore.shared.documents.first { $0.id == reference.id }?.title
        case .space:
            SpaceStore.shared.space(for: reference.id)?.name
        case .reminder, .calendarEvent:
            nil
        }
    }

    /// The sentence for a call, with names filled in where we have them.
    static func sentence(toolNamed name: String, arguments: String) -> String {
        ToolApprovalPrompt.sentence(toolNamed: name, arguments: arguments, resolve: self.name(for:))
    }
}
