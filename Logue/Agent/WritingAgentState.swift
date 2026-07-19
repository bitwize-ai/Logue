import Foundation
import LangGraph

/// LangGraph state for the multi-node writing analysis pipeline.
///
/// Channels define merge strategy:
/// - `Channel<T>()` — overwrites on update
/// - `AppenderChannel<T>()` — appends to array on update
struct WritingAgentState: AgentState {
    // MARK: - Schema

    static var schema: Channels = [
        "text": Channel<String>(),
        "cursor_offset": Channel<Int>(),
        "goal_mode": Channel<String>(),
        "context_window": Channel<String>(),
        "grammar_suggestions": AppenderChannel<SuggestionResponse.SuggestionItem>(),
        "clarity_suggestions": AppenderChannel<SuggestionResponse.SuggestionItem>(),
        "tone_label": Channel<String>(),
        "tone_confidence": Channel<Double>(),
        "word_count": Channel<Int>(),
        "sentence_count": Channel<Int>(),
        "reading_ease": Channel<Double>(),
        "overall_score": Channel<Double>(),
    ]

    // MARK: - Protocol

    var data: [String: Any]
    init(_ initState: [String: Any]) {
        data = initState
    }

    // MARK: - Typed Accessors

    var text: String? {
        value("text")
    }

    var cursorOffset: Int? {
        value("cursor_offset")
    }

    var goalMode: String? {
        value("goal_mode")
    }

    var contextWindow: String? {
        value("context_window")
    }

    var grammarSuggestions: [SuggestionResponse.SuggestionItem]? {
        value("grammar_suggestions")
    }

    var claritySuggestions: [SuggestionResponse.SuggestionItem]? {
        value("clarity_suggestions")
    }

    var toneLabel: String? {
        value("tone_label")
    }

    var toneConfidence: Double? {
        value("tone_confidence")
    }

    var wordCount: Int? {
        value("word_count")
    }

    var sentenceCount: Int? {
        value("sentence_count")
    }

    var readingEase: Double? {
        value("reading_ease")
    }

    var overallScore: Double? {
        value("overall_score")
    }

    /// All suggestions merged and sorted by confidence descending.
    var allSuggestions: [SuggestionResponse.SuggestionItem] {
        let grammar = grammarSuggestions ?? []
        let clarity = claritySuggestions ?? []
        return (grammar + clarity).sorted {
            ($0.confidence.isNaN ? 0 : $0.confidence) > ($1.confidence.isNaN ? 0 : $1.confidence)
        }
    }
}
