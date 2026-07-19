import SwiftUI

/// Protocol for tool enums used with `UnifiedSidebarView`.
protocol ToolbarTool: RawRepresentable, CaseIterable, Identifiable, Equatable where RawValue == String {
    var icon: String { get }
    /// Whether this tool has a live implementation (vs "Coming Soon").
    var isImplemented: Bool { get }
    /// Preferred default panel width for this tool.
    var preferredPanelWidth: CGFloat { get }
    /// Group name for section headers in the tab strip (e.g. "Write", "Review").
    var toolGroup: String { get }
    /// Ordered list of unique group names for section dividers.
    static var groupOrder: [String] { get }
}

/// Sensible defaults so existing conformances don't break.
extension ToolbarTool {
    var isImplemented: Bool {
        true
    }

    var preferredPanelWidth: CGFloat {
        320
    }

    var toolGroup: String {
        ""
    }

    static var groupOrder: [String] {
        [""]
    }
}
