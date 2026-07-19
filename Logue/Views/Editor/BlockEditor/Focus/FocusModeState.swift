import SwiftUI

/// Distraction-free writing mode for the document editor.
///
/// When active, both `MainWindowView` and `DocumentWorkspaceView` observe this state
/// to coordinate hiding the breadcrumb, tool sidebar, and stats bar, and narrowing
/// the editor column. See `DocumentWorkspaceView` and `MainWindowView` for the
/// receiving sides of this signal.
@Observable
@MainActor
final class FocusModeState {
    static let shared = FocusModeState()

    /// Whether focus mode is currently active.
    private(set) var isActive: Bool = false

    /// Max column width for the editor in focus mode. iA Writer uses ~700pt.
    let columnWidth: CGFloat = 720

    private init() {}

    func enter() {
        guard !isActive else { return }
        HapticFeedback.alignment()
        withAnimation(.easeInOut(duration: 0.25)) {
            isActive = true
        }
    }

    func exit() {
        guard isActive else { return }
        HapticFeedback.alignment()
        withAnimation(.easeInOut(duration: 0.2)) {
            isActive = false
        }
    }

    func toggle() {
        if isActive {
            exit()
        } else {
            enter()
        }
    }
}
