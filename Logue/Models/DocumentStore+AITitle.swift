import Foundation

/// Local-LLM title generation for documents.
///
/// Split out of `DocumentStore` so the core type stays within the size the project
/// enforces; the prompts here are long enough to dominate it otherwise.
extension DocumentStore {
    // MARK: - AI Title Generation (Local LLM)

    func generateAITitle(for documentID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("generateAITitle: no model loaded")
            return
        }
        guard let doc = documents.first(where: { $0.id == documentID }) else { return }

        let text = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 50 else { return }

        let prompt = """
        Generate a short title (3-7 words, title case) for this document. \
        Rules: Do NOT include author names or words like "Meeting", "Email", "Document". \
        The title should describe the topic as a noun phrase, not a sentence. \
        Output ONLY the title, nothing else.

        Document:
        \(String(text.prefix(2000)))

        Title:
        """

        if let cleanTitle = await generateTitle(prompt: prompt) {
            if let index = documentIndex(for: documentID),
               isDefaultDocumentTitle(documents[index].title)
            {
                applyTitle(cleanTitle, to: documentID)
            }
        }
    }

    /// Re-generate a title, considering the current title and content changes.
    func regenerateAITitle(for documentID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("regenerateAITitle: no model loaded")
            return
        }
        guard let doc = documents.first(where: { $0.id == documentID }) else { return }

        let text = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 20 else { return }

        let currentTitle = doc.title

        let prompt = if isDefaultDocumentTitle(currentTitle) {
            """
            Generate a short title (3-7 words, title case) for this document. \
            Rules: Do NOT include author names or words like "Meeting", "Email", "Document". \
            The title should describe the topic as a noun phrase, not a sentence. \
            Output ONLY the title, nothing else.

            Document:
            \(String(text.prefix(2000)))

            Title:
            """
        } else {
            """
            The current title is: "\(currentTitle)"
            Below is the document content. If the topic still matches the current title, return the same title. \
            Only generate a new title (3-7 words, title case) if the topic has significantly changed. \
            Do NOT include author names or words like "Meeting", "Email", "Document". \
            Output ONLY the title, nothing else.

            Document:
            \(String(text.prefix(2000)))

            Title:
            """
        }

        if let cleanTitle = await generateTitle(prompt: prompt) {
            // Through `applyTitle` for the deduplication as much as the link repair: this path had
            // neither, so a regenerated title could collide with an existing document's and then
            // win `[[link]]` resolution by being first in the index.
            applyTitle(cleanTitle, to: documentID)
        }
    }

    private func generateTitle(prompt: String) async -> String? {
        await AITitleGenerator.generate(prompt: prompt)
    }

    private func isDefaultDocumentTitle(_ title: String) -> Bool {
        title == "Untitled Document"
    }
}
