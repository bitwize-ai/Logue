import CoreGraphics

/// How far a sidebar may be dragged, given the container it shares with the content.
///
/// Two limits, and the tighter one wins. Neither works alone: a fixed ceiling is cramped
/// on a large display yet still crushes the content pane on a small one, while a purely
/// window-relative limit allows an absurdly wide panel on an ultrawide.
///
/// Pure by design — one function of container width, so it is tested directly rather
/// than through a view.
struct SidebarWidthLimit: Equatable, Sendable {
    /// Narrowest the sidebar may be dragged to. Below this its own content stops fitting.
    let minimum: CGFloat
    /// Widest the sidebar is ever useful at, however much display there is.
    let ceiling: CGFloat
    /// What the content pane beside it must keep.
    let minContentWidth: CGFloat

    /// The left navigation column: space and category names, so a wide column is
    /// mostly whitespace.
    static let categorySidebar = SidebarWidthLimit(
        minimum: 200,
        ceiling: 400,
        minContentWidth: AppConstants.Editor.minContentPaneWidth
    )

    /// The right inspector: proofreader lists and chat, which earn more room than the
    /// navigation column does.
    static let inspector = SidebarWidthLimit(
        minimum: 260,
        ceiling: 900,
        minContentWidth: AppConstants.Editor.minContentPaneWidth
    )

    /// A library surface's panel: action items, templates.
    ///
    /// Deliberately not `inspector`. That limit reserves the editor's 720pt reading measure
    /// for the pane beside it, which is right when the pane is a document and wrong when it
    /// is a list of meetings — on a normal window it capped the panel barely above its own
    /// default width. A list stays perfectly usable at 400, so the panel may take the rest.
    static let libraryPanel = SidebarWidthLimit(
        minimum: 260,
        ceiling: 1800,
        minContentWidth: 400
    )

    /// How wide the sidebar may be dragged inside a container this wide.
    ///
    /// A container width of zero means it has not been measured yet, so only the ceiling
    /// applies — better than guessing a limit and snapping the sidebar to it.
    func maximum(inContainerOfWidth containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return ceiling }
        return min(ceiling, max(minimum, containerWidth - minContentWidth))
    }

    /// `width` brought within both limits for a container this wide.
    func clamping(_ width: CGFloat, inContainerOfWidth containerWidth: CGFloat) -> CGFloat {
        min(max(width, minimum), maximum(inContainerOfWidth: containerWidth))
    }
}
