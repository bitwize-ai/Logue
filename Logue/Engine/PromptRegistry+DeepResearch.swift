import Foundation

// MARK: - Deep Research Prompts

extension PromptRegistry {
    enum DeepResearch {
        // MARK: 1. Check Sufficiency

        static let checkSufficiencySystem = PromptTemplate(
            content: withBase("""
            You decide whether a research request is specific enough to investigate. \
            Your job is to either approve the prompt or list clarifying questions.

            Respond in this exact format:
            - Line 1: SUFFICIENT or INSUFFICIENT
            - If INSUFFICIENT: Lines 2+ are 1-3 short clarifying questions, one per line.

            Mark SUFFICIENT when the prompt has a clear topic and intent, even if details are missing. \
            Mark INSUFFICIENT only when key parameters are ambiguous (e.g. unclear scope, audience, \
            timeframe, or domain) such that a useful report cannot be written.

            Output ONLY the format above. No preamble, no explanation.
            """),
            version: "1.0.0",
            key: "deepResearch.checkSufficiency.system"
        )

        static func checkSufficiencyPrompt(query: String) -> String {
            """
            <query>
            \(query)
            </query>
            """
        }

        // MARK: 2. Synthesize Prompt

        static let synthesizePromptSystem = PromptTemplate(
            content: withBase("""
            Rewrite the user's request as a single clear research instruction (one or two sentences). \
            Use the imperative mood ("Compare X and Y…", "Analyze…", "Summarize…"). \
            Preserve every constraint the user gave (scope, timeframe, audience, format). \
            Add nothing the user didn't say. Output ONLY the rewritten instruction — no quotes, no preamble.
            """),
            version: "1.0.0",
            key: "deepResearch.synthesizePrompt.system"
        )

        static func synthesizePromptPrompt(query: String) -> String {
            """
            <query>
            \(query)
            </query>
            """
        }

        // MARK: 3. Plan Sections

        static let planSectionsSystem = PromptTemplate(
            content: withBase("""
            Plan a research report by breaking the topic into 3-6 focused sections. \
            Each section is a JSON object with:
            - "title": 2-6 word section heading (no markdown)
            - "description": one sentence explaining what this section covers
            - "isSearchNeeded": true if external research is required, false if the LLM \
              can write the section from general knowledge alone (e.g. introductions, definitions)

            Output ONLY a valid JSON array. No surrounding text, no markdown fences. \
            Start with [ and end with ]. Each entry should be distinct (no duplicate titles).

            Example:
            [
              {"title": "Background", "description": "Brief context on the topic and why it matters.", "isSearchNeeded": false},
              {"title": "Current State", "description": "What is happening today, with cited sources.", "isSearchNeeded": true}
            ]
            """),
            version: "1.0.0",
            key: "deepResearch.planSections.system"
        )

        static let planSectionsStrictSystem = PromptTemplate(
            content: planSectionsSystem.content
                + "\n\nIMPORTANT: You MUST output ONLY a valid JSON array. No text before or after. Start with [ and end with ].",
            version: "1.0.0",
            key: "deepResearch.planSections.strict"
        )

        static func planSectionsPrompt(synthesizedPrompt: String) -> String {
            """
            <research_instruction>
            \(synthesizedPrompt)
            </research_instruction>
            """
        }

        // MARK: 4. Research Section

        static func researchSectionSystem(synthesizedPrompt: String, sectionTitle: String) -> String {
            withBase("""
            You are researching one section of a larger report.

            Overall research goal:
            \(synthesizedPrompt)

            Current section: "\(sectionTitle)"

            Use the available tools (semantic_search_meetings, semantic_search_documents, \
            and — when enabled — web_search and fetch_web_page) to gather information. \
            Aim for 2-5 tool calls. Do not chain endlessly. Once you have enough material, \
            STOP calling tools and write a 4-6 sentence summary of your findings.

            In the final answer:
            - Cite every claim with the source URL in Markdown format: [text](url).
            - Stay focused on this section's scope; don't drift into other sections.
            - If a tool returned no results, say so plainly rather than inventing facts.
            """)
        }

        static func researchSectionPrompt(sectionTitle: String, sectionDescription: String) -> String {
            """
            <section>
            <title>\(sectionTitle)</title>
            <description>\(sectionDescription)</description>
            </section>

            Begin researching now. Stop after 2-5 tool calls and produce your summary.
            """
        }

        // MARK: 5. Write Draft

        static let writeDraftSystem = PromptTemplate(
            content: withBase("""
            Compose a Markdown research report from the planned sections and their findings.

            Rules:
            - Start with a single H1 title that captures the research goal.
            - Use H2 (##) for each section, in the planned order.
            - Quote findings verbatim where they help; otherwise paraphrase faithfully.
            - Preserve every Markdown link `[text](url)` from the findings — these are the citations.
            - Where multiple findings cite the same source, citation can appear once at the most relevant claim.
            - Keep the writing crisp and information-dense. No filler. No "in conclusion" wrapper unless meaningful.
            - End with a `## Sources` section listing each unique URL once, numbered.

            Output ONLY the Markdown report. No preamble, no JSON, no fences.
            """),
            version: "1.0.0",
            key: "deepResearch.writeDraft.system"
        )

        static func writeDraftPrompt(synthesizedPrompt: String, sectionsBlock: String) -> String {
            """
            <research_goal>
            \(synthesizedPrompt)
            </research_goal>

            <sections>
            \(sectionsBlock)
            </sections>
            """
        }

        // MARK: 6. Diagram Opportunities

        static let diagramOpportunitiesSystem = PromptTemplate(
            content: withBase("""
            Identify 0-3 places in the draft where a visual diagram would meaningfully aid \
            comprehension (architecture, flow, hierarchy, comparison, timeline). For each, \
            output a JSON object with:
            - "section": the H2 heading where the diagram belongs (verbatim, no #)
            - "description": one sentence describing what the diagram should show
            - "mermaid": a complete Mermaid markup snippet that fits the description

            Wrap node text containing spaces in double quotes (e.g. `A["Step 1"]`).

            If no diagram would meaningfully help, output an empty array: []

            Output ONLY a valid JSON array. No surrounding text, no markdown fences.
            """),
            version: "1.0.0",
            key: "deepResearch.diagramOpportunities.system"
        )

        static func diagramOpportunitiesPrompt(draft: String) -> String {
            """
            <draft>
            \(draft)
            </draft>
            """
        }

        // MARK: 7. Finalize

        static let finalizeSystem = PromptTemplate(
            content: withBase("""
            Polish a research report by improving flow, tightening prose, and ensuring all \
            citations remain attached to their claims. Do NOT add new facts. Do NOT change \
            any URLs. Preserve every diagram markdown image embed as-is. Renumber the \
            ## Sources list so each unique URL appears once in citation order.

            Output ONLY the polished Markdown report.
            """),
            version: "1.0.0",
            key: "deepResearch.finalize.system"
        )

        static func finalizePrompt(draft: String) -> String {
            """
            <draft>
            \(draft)
            </draft>
            """
        }
    }
}
