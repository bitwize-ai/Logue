import AppKit
import SwiftUI

/// Shared state machine for AI text polishing, used by CommandCenterView.
@MainActor @Observable
final class PolishEngine {
    // MARK: - State

    enum State: Equatable {
        case idle, processing, result, error
    }

    var state: State = .idle
    var originalText: String = ""
    var selectedMode: WritingMode = .improve
    var result: WritingResult?
    var errorMessage: String?
    var showCopied: Bool = false

    private var currentTask: Task<Void, Never>?

    // MARK: - Actions

    func polish(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        originalText = trimmed
        errorMessage = nil
        result = nil

        withAnimation { state = .processing }

        let prompt = selectedMode.buildPrompt(for: trimmed)

        currentTask?.cancel()
        currentTask = Task {
            do {
                let response = try await LLMEngine.shared.generate(prompt: prompt)
                guard !Task.isCancelled else { return }
                result = WritingResult(
                    improvedText: response,
                    confidence: 0.85,
                    featureId: selectedMode.rawValue
                )
                withAnimation { state = .result }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                withAnimation { state = .error }
            }
        }
    }

    func reprocess(with text: String, mode: WritingMode) {
        selectedMode = mode
        polish(text: text)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        withAnimation { state = .idle }
    }

    func reset() {
        cancel()
        copiedTask?.cancel()
        copiedTask = nil
        originalText = ""
        result = nil
        errorMessage = nil
        showCopied = false
        savedDocumentID = nil
    }

    private var copiedTask: Task<Void, Never>?

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopied = true
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: AppConstants.Delays.copiedToClipboardDismiss)
            guard !Task.isCancelled else { return }
            showCopied = false
        }
    }

    private var savedDocumentID: UUID?

    func saveToDocument(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let id = savedDocumentID,
           let existing = DocumentStore.shared.documents.first(where: { $0.id == id })
        {
            var updated = existing
            updated.body = trimmed
            DocumentStore.shared.updateDocument(updated)
        } else {
            let components = trimmed.components(separatedBy: .newlines)
            let firstLine = components.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Quick Note"
            let title = firstLine.count > 30 ? String(firstLine.prefix(30)) + "..." : firstLine

            let doc = DocumentStore.shared.createDocument(title: title)
            var updated = doc
            updated.body = trimmed
            DocumentStore.shared.updateDocument(updated)
            savedDocumentID = doc.id
        }
    }

    var isProcessing: Bool {
        state == .processing
    }
}
