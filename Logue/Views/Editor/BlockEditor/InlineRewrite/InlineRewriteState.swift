import AppKit
import SwiftUI

/// State machine for the inline-rewrite popover lifecycle.
///
/// Owned per-BlockEditorView. Holds references to the source text view + range so
/// an Accept applies the rewrite to the exact original selection, even if the user
/// scrolled or the cursor moved while the popover was open.
@Observable
@MainActor
final class InlineRewriteState {
    /// Current phase of the rewrite flow.
    enum Phase: Equatable {
        /// No rewrite in progress — popover hidden.
        case idle
        /// User is typing the instruction.
        case awaitingInstruction
        /// LLM call in flight.
        case rewriting
        /// Rewrite returned; showing diff with Accept/Reject/Regenerate.
        case preview
        /// An error occurred — shown inline in the popover.
        case error(String)
    }

    private(set) var phase: Phase = .idle

    /// The text view that owns the selection being rewritten.
    /// Captured when the popover opens so we can apply the replacement later.
    private(set) weak var sourceTextView: NSTextView?

    /// The character range in `sourceTextView` that will be replaced on Accept.
    private(set) var sourceRange: NSRange = .init(location: NSNotFound, length: 0)

    /// The original selected text (for diff display + regenerate).
    private(set) var originalText: String = ""

    /// Where to anchor the popover in the editor's coordinate space.
    private(set) var anchorPosition: CGPoint = .zero

    /// User's instruction. Edited inline while `.awaitingInstruction`.
    var instruction: String = ""

    /// The LLM's rewritten result (shown in `.preview`).
    private(set) var rewrittenText: String = ""

    /// In-flight task for the current rewrite; cancellable on Regenerate or Cancel.
    private var rewriteTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Opens the popover anchored to the given selection.
    func begin(textView: NSTextView, range: NSRange, selectedText: String, anchor: CGPoint) {
        cancel()
        sourceTextView = textView
        sourceRange = range
        originalText = selectedText
        anchorPosition = anchor
        instruction = ""
        rewrittenText = ""
        phase = .awaitingInstruction
    }

    /// Fires the LLM call. Transitions `.awaitingInstruction` → `.rewriting` → `.preview`/`.error`.
    func submitInstruction() {
        guard case .awaitingInstruction = phase else { return }
        let instructionSnapshot = instruction
        let selectionSnapshot = originalText

        phase = .rewriting
        rewriteTask?.cancel()
        rewriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await InlineRewriteEngine.rewrite(
                    selection: selectionSnapshot,
                    instruction: instructionSnapshot
                )
                guard !Task.isCancelled else { return }
                rewrittenText = result
                phase = .preview
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error(error.localizedDescription)
            }
        }
    }

    /// Re-runs the rewrite with the same instruction (user clicked Regenerate).
    func regenerate() {
        guard case .preview = phase else { return }
        phase = .awaitingInstruction
        submitInstruction()
    }

    /// Applies the rewrite to the source text view, replacing the original range.
    /// Returns `true` on success so callers can fire haptic / analytics / scroll updates.
    @discardableResult
    func accept() -> Bool {
        guard case .preview = phase,
              let textView = sourceTextView,
              sourceRange.location != NSNotFound
        else { return false }

        // Verify the range still points at the original text — guards against stale
        // replacements if the user edited the block while the popover was open.
        let currentLength = (textView.string as NSString).length
        guard NSMaxRange(sourceRange) <= currentLength else { return false }
        let currentAtRange = (textView.string as NSString).substring(with: sourceRange)
        guard currentAtRange == originalText else { return false }

        if textView.shouldChangeText(in: sourceRange, replacementString: rewrittenText) {
            textView.replaceCharacters(in: sourceRange, with: rewrittenText)
            textView.didChangeText()
            dismiss()
            return true
        }
        return false
    }

    /// Dismisses the popover without applying.
    func reject() {
        dismiss()
    }

    /// Called by BlockEditorView when selection clears, scroll happens, or user hits Escape.
    func dismiss() {
        cancel()
        phase = .idle
        sourceTextView = nil
        sourceRange = NSRange(location: NSNotFound, length: 0)
        originalText = ""
        rewrittenText = ""
        instruction = ""
    }

    /// Cancels any in-flight rewrite task.
    private func cancel() {
        rewriteTask?.cancel()
        rewriteTask = nil
    }

    // MARK: - Conveniences for the view

    var isVisible: Bool {
        if case .idle = phase {
            return false
        }
        return true
    }

    var isRewriting: Bool {
        if case .rewriting = phase {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case let .error(message) = phase {
            return message
        }
        return nil
    }

    var canSubmit: Bool {
        if case .awaitingInstruction = phase {
            return !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}
