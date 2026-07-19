import SwiftUI

/// Multi-line text input: Enter sends, Shift+Enter inserts a newline.
/// Starts at 1 line, grows up to 5 lines, then scrolls.
struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void
    /// Set to `true` to programmatically focus the input field. Resets to `false` after focusing.
    @Binding var requestFocus: Bool

    /// Maximum visible lines before scrolling kicks in.
    private static let maxLines = 5

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = SubmittableTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.preferredFont(forTextStyle: .subheadline)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.placeholderString = "Ask anything…"

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Set initial single-line height
        let lineHeight = (textView.font ?? NSFont.systemFont(ofSize: 13)).boundingRectForFont.height
        DispatchQueue.main.async {
            height = ceil(lineHeight)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittableTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }
        textView.onSubmit = onSubmit
        if requestFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                // Place cursor at end of text
                textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
                requestFocus = false
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: ChatInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            recalcHeight()
        }

        func recalcHeight() {
            guard let tv = textView,
                  let container = tv.textContainer,
                  let manager = tv.layoutManager
            else { return }

            manager.ensureLayout(for: container)
            let usedRect = manager.usedRect(for: container)
            let contentHeight = usedRect.height + tv.textContainerInset.height * 2

            let lineHeight = (tv.font ?? NSFont.systemFont(ofSize: 13)).boundingRectForFont.height
            let maxHeight = ceil(lineHeight * CGFloat(ChatInputField.maxLines))
            let singleLine = ceil(lineHeight)

            let clamped = max(singleLine, min(contentHeight, maxHeight))

            DispatchQueue.main.async {
                self.parent.height = clamped
            }
        }
    }
}

/// NSTextView subclass that intercepts Enter (send) vs Shift+Enter (newline).
class SubmittableTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholderString: String = ""

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let shiftHeld = event.modifierFlags.contains(.shift)

        if isReturn, !shiftHeld {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty {
            drawPlaceholder(in: dirtyRect)
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func drawPlaceholder(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.preferredFont(forTextStyle: .subheadline),
        ]
        let placeholder = NSAttributedString(string: placeholderString, attributes: attrs)
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        // Anchor at the text container's top-left so the placeholder sits on
        // the same baseline as the cursor/typed text. The previous vertical-
        // centering math drifted the placeholder down while the cursor stayed
        // pinned to the top of the container.
        placeholder.draw(at: NSPoint(x: inset.width + padding, y: inset.height))
    }
}
