import AppKit
import SwiftUI

/// A transparent overlay view that sets the pointer (hand) cursor via AppKit's
/// resetCursorRects mechanism. This is more reliable than NSCursor.push/pop
/// in onHover because it fires after NSButton's own tracking areas are evaluated,
/// preventing NSButton from resetting the cursor to the arrow.
///
/// Usage:
///   someView.overlay(HandCursorArea())
struct HandCursorArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> CursorRectView {
        CursorRectView()
    }

    func updateNSView(_: CursorRectView, context _: Context) {}

    final class CursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        /// Transparent to mouse clicks — only handles cursor rects.
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
