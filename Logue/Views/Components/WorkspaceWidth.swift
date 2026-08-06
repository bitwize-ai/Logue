import SwiftUI

/// The full width of the workspace an inspector sidebar sits in.
///
/// The sidebar's resize limit is expressed against the workspace rather than as a
/// fixed number of points, so how far the panel may be dragged is decided by the
/// window the user actually has, not by a constant chosen years earlier.
///
/// Zero means "not measured yet", which readers take as "no limit to apply".
private struct WorkspaceWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var workspaceWidth: CGFloat {
        get { self[WorkspaceWidthKey.self] }
        set { self[WorkspaceWidthKey.self] = newValue }
    }
}

/// Reduces by `max` so a nested measurement — a workspace inside the window — never
/// reports a width smaller than the container that also reads this key.
private struct ViewWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Publishes this workspace's width to descendants as `\.workspaceWidth`.
///
/// Safe against a layout loop: the width published is the container's own, which the
/// window decides. Nothing downstream that consumes it can change it.
///
/// Apply this to a workspace, not to the window's `NavigationSplitView`. That split view
/// persists any `.detailOnly` it reports, so writing state during its first layout risks
/// it recording the sidebar as dismissed — see `MainWindowView.columnVisibility`.
private struct WorkspaceWidthMeasure: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ViewWidthPreferenceKey.self,
                        value: geometry.size.width
                    )
                }
            )
            .onPreferenceChange(ViewWidthPreferenceKey.self) { width = $0 }
            .environment(\.workspaceWidth, width)
    }
}

extension View {
    /// Publishes this workspace's width to descendants as `\.workspaceWidth`.
    func measuringWorkspaceWidth() -> some View {
        modifier(WorkspaceWidthMeasure())
    }
}
