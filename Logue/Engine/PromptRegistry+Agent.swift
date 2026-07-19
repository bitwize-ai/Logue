import Foundation

// MARK: - Agent Prompts

extension PromptRegistry {
    enum Agent {
        /// Builds the agent system prompt for the **current** run. Tailoring the
        /// listing to actually-registered tools matters because:
        ///
        /// - Listing tools that aren't registered makes the LLM try (and fail)
        ///   to call them, wasting a turn.
        /// - Hiding tools that ARE registered means the LLM doesn't know to use
        ///   them, even though the user enabled them.
        /// - When the user flips the per-message Search toggle, an explicit
        ///   directive nudges weaker local models to actually reach for web
        ///   search instead of falling back on stale training data.
        static func systemPrompt(webSearchAvailable: Bool, oneShotWebSearch: Bool) -> String {
            // Phase A: user can override the entire system prompt via Settings
            // → AI → "System prompt". Empty / whitespace-only override falls
            // back to the built-in default below.
            let override = (UserDefaults.standard.string(
                forKey: AppConstants.UserDefaultsKeys.agentSystemPromptOverride
            ) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !override.isEmpty {
                return withBase(override)
            }

            let toolFamilies = makeToolFamilies(webSearchAvailable: webSearchAvailable)
            let webGuidance = makeWebGuidance(
                webSearchAvailable: webSearchAvailable,
                oneShotWebSearch: oneShotWebSearch
            )
            return withBase("""
            You are Logue's AI assistant. You help the user work with their meetings, \
            documents, spaces, action items, calendar, and templates.

            \(toolFamilies)

            Search guidance:
            - Use `search_meetings` / `search_documents` for exact keyword matches.
            - Use `semantic_search_meetings` / `semantic_search_documents` for concept or \
              meaning-based queries (e.g. "when did we discuss backpressure?"). Try this \
              first when the user asks "what did we say about X" — it surfaces matches even \
              if the exact word never appeared.\(webGuidance)

            Rules:
            - Mutating actions (create_document, update_document, delete_document, \
              create_space, rename_space, delete_space, create_calendar_event, \
              export_document_pdf, etc.) require user approval. Deletes additionally \
              require Touch ID. Before calling a mutating tool, briefly explain WHAT you \
              will do and WHY in plain language so the user can approve or reject with context.
            - When the user describes an entity ("my planning doc", "yesterday's standup"), \
              search or list first to resolve the ID — do not guess UUIDs.
            - When chaining tools, prefer one tool at a time so you can adapt to results. \
              For simple read-only lookups you may parallelise.
            - Cite meeting or document titles and dates in your answers.
            - If no results found, say so clearly.
            - Be concise. Use structured formatting for lists and tables.
            """)
        }

        private static func makeToolFamilies(webSearchAvailable: Bool) -> String {
            let webLine = webSearchAvailable ? "- Web: web_search, fetch_web_page" : ""
            return """
            Tool families available to you:
            - Read: list_meetings, search_meetings, semantic_search_meetings, \
              get_meeting_details, get_transcript, get_action_items, get_daily_digest, \
              list_documents, search_documents, semantic_search_documents, get_document, \
              get_upcoming_events, list_templates, get_reminders, fetch_contacts
            - Write: create_document, update_document, delete_document, move_document, \
              add_document_tag, create_space, rename_space, delete_space, \
              create_calendar_event, create_document_from_template, export_document_pdf, \
              add_reminder, draft_email
            - AI-on-content: summarize_document, rephrase_text, check_grammar, \
              check_clarity, detect_tone, fact_check_document, detect_pii
            - Visual: render_diagram (Mermaid → SVG, embedded inline as Markdown image)
            - Compute: run_javascript (sandboxed JSContext for math, regex, JSON, transformations)
            - Interactive: get_confirmation (yes/no dialog), get_text_input (free-text dialog)
            \(webLine)
            """
        }

        private static func makeWebGuidance(webSearchAvailable: Bool, oneShotWebSearch: Bool) -> String {
            guard webSearchAvailable else { return "" }
            if oneShotWebSearch {
                return """


                The user has EXPLICITLY enabled Web Search for this message. \
                For any question that benefits from current information, real-time \
                data, current events, public facts, definitions, or anything that \
                your training data may not have or may be stale on, you MUST call \
                `web_search` first to gather sources, then optionally `fetch_web_page` \
                on the most relevant result for full content. Cite the URLs in your \
                answer using Markdown links: [text](url).
                """
            }
            return """


            Web search guidance: use `web_search` for current events, real-time \
            data, or facts that may not be in your training data. Always cite \
            source URLs with Markdown links: [text](url).
            """
        }

        /// Default static prompt — used by callers that don't have run-time
        /// state (e.g. one-off tests, prompt versioning). The dynamic
        /// `systemPrompt(webSearchAvailable:oneShotWebSearch:)` is the source
        /// of truth for the agent loop.
        static let system = PromptTemplate(
            content: systemPrompt(webSearchAvailable: false, oneShotWebSearch: false),
            version: "4.0.0",
            key: "agent.system"
        )

        /// v3.0.0 — Quick prompt suggestions for the empty chat state.
        static let emptyStatePrompts: [String] = [
            "What action items are overdue?",
            "Summarize my most recent meeting",
            "Create a new document called \"Weekly Plan\"",
            "Find all documents about onboarding and create a consolidated summary",
            "Check the grammar on my latest document",
            "Export my pricing doc to PDF",
        ]
    }
}
