import Foundation

/// The chips offered under the greeting.
///
/// Split from the view for the same reason as `HomeAskPrompts`: which chips appear is a
/// rule about the workspace, not about layout, and a rule can be tested. The ordering is
/// deliberately fixed rather than ranked — a chip that moves between renders reads as a
/// glitch, and the user is aiming at a target that has already shifted.
enum HomeSuggestions {
    /// A chip carries two strings: the short one it shows, and the full sentence it
    /// puts in the input. Showing the full sentence would make a chip a paragraph.
    struct Chip: Equatable, Identifiable {
        let label: String
        let prompt: String
        var id: String { label }
    }

    /// What the workspace looks like right now, reduced to only what chip selection needs.
    struct Inputs {
        var unsummarizedMeetingTitle: String?
        var overdueCount: Int
        var meetingsToday: Int
        var hasAnyContent: Bool
    }

    static let maximum = 3

    /// Shown before the workspace has anything in it, where nothing can be named yet.
    /// These teach capability instead, which is the only thing left to offer.
    static let firstRunChips: [Chip] = [
        Chip(label: "What can you do?", prompt: "What can you do?"),
        Chip(label: "Record my next meeting", prompt: "Record my next meeting"),
        Chip(
            label: "Draft a document",
            prompt: "Draft a document from an outline I will give you"
        ),
    ]

    static func chips(for inputs: Inputs) -> [Chip] {
        guard inputs.hasAnyContent else { return firstRunChips }

        var chips: [Chip] = []

        if let title = inputs.unsummarizedMeetingTitle {
            let name = HomeAskPrompts.sanitize(title, fallback: "Untitled meeting")
            chips.append(
                Chip(
                    label: "Summarize “\(name)”",
                    prompt: HomeAskPrompts.meeting(title: title, isSummarized: false)
                )
            )
        }
        if inputs.overdueCount > 0 {
            chips.append(Chip(label: "What’s overdue?", prompt: "What’s overdue?"))
        }
        if inputs.meetingsToday > 0 {
            chips.append(Chip(label: "What did I miss today?", prompt: "What did I miss today?"))
        }
        if chips.isEmpty {
            chips.append(Chip(label: "What can you do?", prompt: "What can you do?"))
        }

        return Array(chips.prefix(maximum))
    }
}
