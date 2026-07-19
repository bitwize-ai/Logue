import SwiftUI

// MARK: - EditorTool

/// All tool panels available in the right sidebar of the document editor.
enum EditorTool: String, CaseIterable, Identifiable, ToolbarTool {
    // Write group
    case aiChat = "AI Assistant"
    case proofreader = "Proofreader"
    case review = "Review"
    // Refine group
    case rewrite = "Rewrite"
    case vocabularyEnhancement = "Vocabulary"
    case verify = "Verify"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .aiChat: "sparkles.rectangle.stack"
        case .proofreader: "checkmark.shield"
        case .review: "checkmark.seal"
        case .rewrite: "arrow.clockwise.circle"
        case .vocabularyEnhancement: "textformat.alt"
        case .verify: "shield.lefthalf.filled"
        }
    }

    var toolGroup: String {
        switch self {
        case .aiChat, .proofreader, .review:
            "Write"
        case .rewrite, .vocabularyEnhancement, .verify:
            "Refine"
        }
    }

    static var groupOrder: [String] {
        ["Write", "Refine"]
    }

    var preferredPanelWidth: CGFloat {
        switch self {
        case .aiChat: 360
        case .review: 340
        case .rewrite, .proofreader, .verify: 320
        case .vocabularyEnhancement: 300
        }
    }
}
