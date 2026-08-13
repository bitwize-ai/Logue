import Foundation

/// The right-panel tools of the All Meetings surface.
///
/// One case today. The enum exists rather than a bare boolean so a second lens on the
/// meeting library costs a case instead of a rewrite — the same shape `MeetingTool` uses
/// for a single meeting's panels.
enum MeetingsLibraryTool: String, CaseIterable, Identifiable, ToolbarTool {
    case actionItems = "Action Items"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .actionItems: "checklist"
        }
    }

    var toolGroup: String { "Library" }

    static var groupOrder: [String] { ["Library"] }

    var preferredPanelWidth: CGFloat {
        switch self {
        case .actionItems: 340
        }
    }
}

/// The right-panel tools of the All Documents surface.
enum DocumentsLibraryTool: String, CaseIterable, Identifiable, ToolbarTool {
    case templates = "Templates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .templates: "doc.on.doc"
        }
    }

    var toolGroup: String { "Library" }

    static var groupOrder: [String] { ["Library"] }

    var preferredPanelWidth: CGFloat {
        switch self {
        case .templates: 320
        }
    }
}
