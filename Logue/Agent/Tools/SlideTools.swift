import Foundation
import MLXLMCommon

// MARK: - GenerateSlideDeckTool

/// Phase H: agent-callable slide deck generator. Replaces the standalone
/// Slide Studio sidebar entry — the user asks the chat to draft slides on
/// a topic, the LLM picks up conversation context (prior turns + uploaded
/// attachments) and calls this tool with a condensed `topic`. The tool
/// asks `SlideDeckBuilder` to draft an HTML deck and pushes it into the
/// Canvas pane for live preview + PDF export.
struct GenerateSlideDeckTool: AgentTool {
    let name = "generate_slides"
    let description = """
    Generate a presentation deck on a given topic and open it in the Canvas pane for the user. \
    Use when the user asks for slides, a presentation, a deck, a pitch outline, or similar. \
    The deck is rendered as HTML inside Canvas; the user can export to PDF from there.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "topic": AgentToolSpec.stringParam(
                    "Topic for the deck. Pre-condense relevant context from the conversation " +
                        "and attachments into one focused brief."
                ),
                "slide_count": AgentToolSpec.intParam(
                    "How many slides to generate. Default 8, capped at \(SlideDeckBuilder.maxSlides)."
                ),
            ],
            required: ["topic"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let topic = (arguments["topic"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty
        else {
            throw AgentToolError.missingParameter("topic")
        }
        let requested = arguments["slide_count"] as? Int ?? 8
        let slideCount = max(3, min(SlideDeckBuilder.maxSlides, requested))

        do {
            let html = try await SlideDeckBuilder.generate(prompt: topic, slideCount: slideCount)
            // Push into Canvas on the main actor so the right-side pane
            // surfaces the deck immediately. Language tag "slidedeck" is
            // routed through the existing HTML preview path inside
            // CanvasPaneView (added in this same phase).
            await MainActor.run {
                CanvasController.shared.push(content: html, language: "slidedeck")
            }
            return "Generated a \(slideCount)-slide deck on \"\(topic)\" and opened it in the Canvas pane. "
                + "The user can flip through the slides, iterate by sending a follow-up, or export to PDF."
        } catch let error as SlideDeckBuilder.SlideError {
            throw AgentToolError.executionFailed(error.localizedDescription)
        } catch {
            throw AgentToolError.executionFailed("Slide generation failed: \(error.localizedDescription)")
        }
    }
}
