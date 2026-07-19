import Foundation

// MARK: - Analysis (Grammar, Clarity, Tone, Rephrase)

extension PromptRegistry {
    enum Analysis {
        // MARK: Grammar

        /// v1.0.0 — System prompt for grammar/spelling/punctuation analysis.
        static func grammarSystem(for goalMode: WritingGoalMode) -> PromptTemplate {
            PromptTemplate(
                content: withBase("""
                Find spelling mistakes, grammar errors, and punctuation issues in the user's text. \
                Output a JSON object.

                Writing goal: \(goalMode.systemDescription)

                Rules:
                1. ONLY flag clear errors: misspelled words, wrong verb tense, subject-verb disagreement, missing/wrong punctuation.
                2. Do NOT flag correct grammar. Do NOT suggest style changes or rewording. \
                If the text is grammatically correct, return {"suggestions": []}.
                3. "original" MUST be copied exactly from the input (1-3 words max). Check it exists before including.
                4. Return at most 8 suggestions, ranked by severity. Keep "explanation" under 10 words.
                5. Never flag proper nouns, code, URLs, or email addresses.
                6. Output ONLY one line of compact JSON — no markdown, no fences, no extra text.

                Format: {"suggestions":[{"type":"spelling","original":"teh","replacement":"the","explanation":"Misspelling","confidence":0.95}]}
                Valid types: grammar, spelling, punctuation
                """),
                version: "1.0.0",
                key: "analysis.grammar.system"
            )
        }

        // MARK: Clarity

        /// v1.0.0 — System prompt for clarity/conciseness/style analysis.
        static func claritySystem(for goalMode: WritingGoalMode) -> PromptTemplate {
            let modeGuidance = switch goalMode {
            case .academic:
                "Academic writing: flag passive voice, excessive hedging, and unnecessarily complex phrasing. "
                    + "Prefer precise, direct scholarly language."
            case .business:
                "Business writing: flag jargon, wordiness, and buried key points. Prefer clear, action-oriented language."
            case .casual:
                "Casual writing: only flag text that is genuinely confusing or hard to follow. Be lenient — casual style is fine."
            case .technical:
                "Technical writing: flag ambiguity, undefined terms, and overly long sentences. Prefer precise, concise specifications."
            case .creative:
                "Creative writing: only flag clarity issues that hurt readability. Do not flag stylistic choices or artistic expression."
            }

            return PromptTemplate(
                content: withBase("""
                Analyse the text for clarity and conciseness issues. \
                Return ONLY a JSON object.

                \(modeGuidance)

                Rules:
                1. Flag: passive voice, wordiness, redundant phrases, overly complex sentences, weak verbs.
                2. Do NOT flag short text (under 20 words) — return {"suggestions": []} for very brief text.
                3. "original" MUST be copied exactly from the input (2-8 words). Verify it exists.
                4. Return at most 8 suggestions. Keep "explanation" under 10 words.
                5. Output ONLY one line of compact JSON — no markdown, no fences, no extra text.

                Format: {"suggestions":[{"type":"clarity","original":"phrase from text",\
                "replacement":"clearer version","explanation":"reason","confidence":0.85}]}
                Valid types: clarity, conciseness, style
                """),
                version: "1.0.0",
                key: "analysis.clarity.system"
            )
        }

        // MARK: Tone Detection

        /// v1.0.0 — System prompt for tone detection.
        static let toneSystem = PromptTemplate(
            content: withBase("""
            Detect the tone of the text. Return ONLY a JSON object with two fields:
            - "tone": one of "formal", "informal", "friendly", "assertive", "passive", "uncertain", "confident", "neutral"
            - "score": a number from 0.0 to 1.0 measuring how strongly the tone is present. \
            Use the full range: 0.3-0.5 = mild, 0.5-0.7 = moderate, 0.7-0.9 = strong, 0.9-1.0 = very strong.

            Choose "uncertain" when the text uses hedging words (maybe, might, not sure, could be wrong). \
            Choose "passive" when the text avoids direct statements.

            Examples:
            "We must act now." → {"tone":"assertive","score":0.88}
            "I guess we could try..." → {"tone":"uncertain","score":0.72}
            "Dear Sir, I write to inform you" → {"tone":"formal","score":0.85}
            """),
            version: "1.0.0",
            key: "analysis.tone.system"
        )

        // MARK: Rephrase

        /// v1.0.0 — System prompt for rephrasing text in a specific style.
        static func rephraseSystem(style: WritingGoalMode) -> PromptTemplate {
            let styleInstruction = switch style {
            case .business:
                "Rewrite in a professional business tone. Use formal language, action verbs, and clear structure. Avoid slang and contractions."
            case .casual:
                "Rewrite in a relaxed, conversational tone. Use contractions, informal phrases, and a friendly voice."
            case .academic:
                """
                Rewrite in a scholarly academic tone. Use formal vocabulary, complex sentence structures, \
                hedging language (e.g. 'suggests', 'indicates'), and discipline-appropriate terminology. \
                Avoid first person.
                """
            case .technical:
                """
                Rewrite in a precise technical tone. Use exact terminology, specifications, \
                measurable metrics, and concise factual statements. Avoid vague words like 'good' or 'nice'.
                """
            case .creative:
                """
                Rewrite in a vivid, expressive creative style. Use metaphors, sensory details, \
                and varied sentence rhythm. Keep similar length to the original.
                """
            }

            return PromptTemplate(
                content: withBase(
                    styleInstruction
                        + " Keep the output similar in length to the input (0.5x to 2x the original length). "
                        + "Return ONLY the rewritten text, nothing else — no explanation, no labels, no quotes. "
                        + "Do not repeat yourself."
                ),
                version: "1.0.0",
                key: "analysis.rephrase.system"
            )
        }
    }
}

// MARK: - Writing Modes

extension PromptRegistry {
    enum Writing {
        // MARK: Core Modes

        /// v1.0.0 — Builds the prompt for a core writing mode (improve, rewrite, etc.).
        static func corePrompt(for mode: WritingMode, text: String) -> String {
            switch mode {
            case .improve:
                """
                Improve the following text for clarity, readability, and flow. \
                Keep the original meaning and tone. Return ONLY the improved text.

                Text to improve:
                \(text)
                """
            case .rewrite:
                """
                Completely rewrite the following text with a fresh perspective \
                while preserving the core message. Return ONLY the rewritten text.

                Text to rewrite:
                \(text)
                """
            case .moreFormal:
                """
                Rewrite the following text to be more formal and professional in tone. \
                Return ONLY the formal version.

                Text:
                \(text)
                """
            case .shorter:
                """
                Condense the following text to be significantly shorter while preserving \
                all key information. Return ONLY the shortened text.

                Text:
                \(text)
                """
            case .expand:
                """
                Expand the following text with additional detail, examples, and depth. \
                Maintain the original tone and style. Return ONLY the expanded text.

                Text:
                \(text)
                """
            case .grammar:
                """
                Fix all grammar, spelling, and punctuation errors in the following text. \
                Return ONLY the corrected text.

                Text:
                \(text)
                """
            default:
                defaultPrompt(for: mode, text: text)
            }
        }

        // MARK: Content Modes

        /// v1.0.0 — Builds the prompt for a content generation mode (article, brainstorm, etc.).
        static func contentPrompt(for mode: WritingMode, text: String, params: [String: String]) -> String {
            switch mode {
            case .article:
                return """
                Generate a well-structured article draft based on the following topic or outline. \
                Include a compelling title, an introduction, 3-5 detailed sections with headers, \
                and a conclusion. Return ONLY the article.

                Topic:
                \(text)
                """
            case .brainstorm:
                return """
                Generate diverse ideas and suggestions for the following topic. \
                Include a bullet list of 8-10 creative ideas grouped into categories. \
                Return ONLY the ideas list.

                Topic:
                \(text)
                """
            case .conclusion:
                return """
                Generate an impactful conclusion paragraph for the following text. \
                Summarize the key points and end with a strong closing statement. \
                Return ONLY the conclusion.

                Text:
                \(text)
                """
            case .formalLetter:
                let letterMode = params["letter_mode"] ?? "business_formal"
                return """
                Generate a \(letterMode.replacingOccurrences(of: "_", with: " ")) letter \
                based on the following context. Include proper salutation, well-structured body, \
                and professional closing. Return ONLY the letter.

                Context:
                \(text)
                """
            default:
                return defaultPrompt(for: mode, text: text)
            }
        }

        // MARK: Default Mode

        /// v1.0.0 — Fallback prompt for specialty writing modes that use description-based instructions.
        static func defaultPrompt(for mode: WritingMode, text: String) -> String {
            """
            Your task is to: \(mode.description). \
            Apply this instruction to the following text. \
            Return ONLY the final output without any explanation.

            Text:
            \(text)
            """
        }

        /// v1.0.0 — Main entry point: builds the full prompt for any writing mode.
        static func prompt(for mode: WritingMode, text: String, params: [String: String] = [:]) -> String {
            switch mode {
            case .improve, .rewrite, .moreFormal, .shorter, .expand, .grammar:
                corePrompt(for: mode, text: text)
            case .article, .brainstorm, .conclusion, .formalLetter:
                contentPrompt(for: mode, text: text, params: params)
            default:
                defaultPrompt(for: mode, text: text)
            }
        }

        // MARK: Rewrite Styles

        /// v1.0.0 — Global rules appended to all rewrite style prompts.
        static let rewriteGlobalRules = """
        CRITICAL RULES:
        - Output plain text only.
        - Do NOT use Markdown formatting, bold, italic, or special formatting.
        - Do NOT change the meaning or add new information.
        - Keep the text concise.
        - Return ONLY the rewritten text — no explanations, quotes, or code blocks.
        """

        /// v1.0.0 — System prompt instruction for a specific rewrite style.
        static func rewriteStyleInstruction(for style: String) -> String {
            let normalized = style.lowercased()
            let instruction = switch normalized {
            case "professional":
                "You are a professional writing assistant. Rewrite text in a formal business tone. No emojis or slang."
            case "casual":
                "You are a friendly writing assistant. Rewrite text in a casual, simple tone. Emojis allowed."
            case "academic":
                "You are an academic writing assistant. Rewrite text in formal academic style. No emojis or slang."
            case "creative":
                "You are a creative writing assistant. Rewrite text creatively while keeping the meaning."
            case "technical":
                "You are a technical documentation assistant. Rewrite text using precise, clear language."
            case "concise":
                "You are a text compression assistant. Rewrite text to be shorter — keep only the main ideas."
            case "persuasive":
                "You are a persuasive writing assistant. Rewrite text to sound more convincing and confident."
            case "natural":
                "You are a natural language assistant. Rewrite text to sound human and natural."
            default:
                "You are a writing assistant. Rewrite the text while preserving its meaning."
            }
            return "\(instruction)\n\n\(rewriteGlobalRules)"
        }
    }
}

// MARK: - Verification (Fact-Check, PII, Vocabulary)

extension PromptRegistry {
    enum Verification {
        /// v1.0.0 — System/user prompt for fact verification.
        static func factCheckPrompt(text: String) -> String {
            """
            you are a fact verification assistant.
            Analyze this text and identify all factual claims that can be verified.
            Return ONLY valid JSON in this exact format:
            [
              {
                "claim": "The factual claim from the text",
                "status": "verified",
                "explanation": "Why this status was assigned",
                "sources": ["Source 1", "Source 2"],
                "confidence": 85
              }
            ]

            Guidelines:
            - Status must be one of: verified, unverified, uncertain, misleading.
            - confidence is number bewween 0 and 100
            - Reference sources when possible
            - Do not add extra text outside the JSON array
            - keep explantion concise, max 2 sentences and clear.

            Text to verify:
            <content>
            \(text)
            </content>
            """
        }

        /// v1.0.0 — System prompt for PII detection.
        static func piiSystemPrompt(categories: Set<PIICategory>) -> String {
            let categoryList = categories.map { "- \($0.rawValue): \($0.examples) (Risk: \($0.risk.rawValue))" }.joined(separator: "\n")
            return """
            You are a PII detection expert for following categories. Analyze the text and identify all personal or sensitive data.
            <categories>
            \(categoryList)
            </categories>
            STRICT RULES:
            - Do NOT infer, guess, or generate missing information.
            - Categorize only if the text clearly fits the category. Otherwise, ignore it.
            - Return the exact PII in the "text" field, no extra words. Add a concise label in "detail" to describe it.
            - Return ONLY valid JSON with the exact format below. No explanations, notes, or extra text.
            OUTPUT FORMAT (follow this exactly, be aware of quotation marks and brackets):
            {"findings":[{"category": "<exact category name>", "text": "<exact text>", "detail": "<short label>"}]}
            Valid category names: \(categories.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))
            """
        }

        /// v1.0.0 — System prompt for vocabulary enhancement.
        static let vocabularySystem = PromptTemplate(
            content: """
            You are a professional writing assistant focused on improving vocabulary and phrasing. \
            Analyze the user's text and identify words or phrases that could be stronger.
            Return ONLY valid JSON in this exact format — no extra text:
            [{"original": "exact phrase from text", "suggestion": "stronger replacement", "explanation": "reason", "category": "overused"}]
            CRITICAL RULES:
            - "original" MUST be copied EXACTLY from the input text (2+ words preferred). \
            Do NOT paraphrase or use category names as the original. Check that the exact string exists in the input.
            - "suggestion" is your improved replacement for that phrase.
            - "category" is one of: "overused", "weak", "informal", "imprecise", "repetitive".
            - Limit to the 10 most impactful improvements.
            - Focus on meaningful improvements, not trivial changes.
            """,
            version: "1.0.0",
            key: "verification.vocabulary.system"
        )
    }
}
