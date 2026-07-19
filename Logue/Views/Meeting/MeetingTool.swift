import Foundation

/// Tools available in the meeting workspace right panel.
enum MeetingTool: String, CaseIterable, Identifiable, ToolbarTool {
    // Review group
    case aiChat = "AI Chat"
    case summary = "Summary"
    case actionItems = "Action Items"
    // Details group
    case speakers = "Speakers"
    case bookmarks = "Bookmarks"
    case recording = "Recording"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .summary: "doc.plaintext"
        case .bookmarks: "bookmark"
        case .actionItems: "checklist"
        case .aiChat: "sparkles.rectangle.stack"
        case .speakers: "person.2"
        case .recording: "waveform"
        }
    }

    var toolGroup: String {
        switch self {
        case .aiChat, .summary, .actionItems:
            "Review"
        case .speakers, .bookmarks, .recording:
            "Details"
        }
    }

    static var groupOrder: [String] {
        ["Review", "Details"]
    }

    var preferredPanelWidth: CGFloat {
        switch self {
        case .aiChat: 360
        case .summary: 340
        case .actionItems, .speakers, .bookmarks, .recording: 300
        }
    }
}
