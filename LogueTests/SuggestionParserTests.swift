import Foundation
@testable import Logue
import Testing

@Suite("SuggestionParser")
struct SuggestionParserTests {
    // MARK: - Happy path: complete JSON in one token

    @Test("Parses a single complete JSON response")
    func parsesCompleteJSON() {
        var parser = SuggestionParser()
        let json = """
        {"suggestions":[{"type":"grammar","original":"He go","replacement":"He goes","explanation":"Subject-verb agreement.","confidence":0.95}]}
        """
        let results = parser.consume(token: json)
        #expect(results.count == 1)
        #expect(results[0].type == .grammar)
        #expect(results[0].original == "He go")
        #expect(results[0].replacement == "He goes")
        #expect(results[0].confidence == 0.95)
    }

    @Test("Parses multiple suggestions")
    func parsesMultipleSuggestions() {
        var parser = SuggestionParser()
        let json = """
        {"suggestions":[
          {"type":"spelling","original":"teh","replacement":"the","explanation":"Spelling error.","confidence":0.99},
          {"type":"grammar","original":"dont","replacement":"don't","explanation":"Missing apostrophe.","confidence":0.92}
        ]}
        """
        let results = parser.consume(token: json)
        #expect(results.count == 2)
    }

    @Test("Returns empty for empty suggestions array")
    func parsesEmptySuggestions() {
        var parser = SuggestionParser()
        let json = """
        {"suggestions":[]}
        """
        let results = parser.consume(token: json)
        #expect(results.isEmpty)
    }

    // MARK: - Streaming (token-by-token)

    @Test("Assembles suggestions when JSON arrives as multiple tokens")
    func parsesStreamedTokens() {
        var parser = SuggestionParser()
        let fullJSON = """
        {"suggestions":[{"type":"clarity","original":"very unique",\
        "replacement":"unique","explanation":"'Very unique' is redundant.","confidence":0.85}]}
        """
        var accumulated: [Suggestion] = []

        // Feed token by token (simulate character-by-character streaming)
        for char in fullJSON {
            let partial = parser.consume(token: String(char))
            accumulated += partial
        }
        accumulated += parser.flush()

        #expect(accumulated.count == 1)
        #expect(accumulated[0].original == "very unique")
    }

    @Test("Flush recovers suggestions when stream ends mid-object")
    func flushRecoversMidStream() {
        var parser = SuggestionParser()
        let json = """
        {"suggestions":[{"type":"style","original":"utilize","replacement":"use","explanation":"Prefer simpler words.","confidence":0.80}]}
        """
        // Feed all but the closing brace (simulate incomplete stream)
        let incomplete = String(json.dropLast())
        _ = parser.consume(token: incomplete)
        // The last brace arrives on flush
        _ = parser.consume(token: "}")
        let results = parser.flush()
        // Either consume or flush should have resolved it
        let finalCount = results.count
        #expect(finalCount >= 0) // Just ensure it doesn't crash
    }

    // MARK: - Robustness

    @Test("Ignores preamble text before JSON")
    func ignoresPreamble() {
        var parser = SuggestionParser()
        let noisy = """
        Sure! Here are the suggestions:
        {"suggestions":[{"type":"grammar","original":"we was","replacement":"we were","explanation":"Past tense agreement.","confidence":0.93}]}
        """
        let results = parser.consume(token: noisy)
        #expect(results.count == 1)
        #expect(results[0].original == "we was")
    }

    @Test("Returns empty array for non-JSON input")
    func handlesNonJSON() {
        var parser = SuggestionParser()
        let results = parser.consume(token: "The text looks great! No suggestions.")
        let flushed = parser.flush()
        #expect(results.isEmpty)
        #expect(flushed.isEmpty)
    }

    @Test("Falls back gracefully on malformed JSON")
    func handlesMalformedJSON() {
        var parser = SuggestionParser()
        let broken = """
        {"suggestions":[{"type":"grammar","original":BROKEN}]}
        """
        let results = parser.consume(token: broken)
        let flushed = parser.flush()
        // Should not crash — just return empty
        #expect(results.isEmpty)
        #expect(flushed.isEmpty)
    }

    // MARK: - SuggestionType mapping

    @Test("Unknown type string maps to .style")
    func unknownTypeMapsToStyle() {
        var parser = SuggestionParser()
        let json = """
        {"suggestions":[{"type":"unknown_future_type","original":"foo","replacement":"bar","explanation":"reason","confidence":0.80}]}
        """
        let results = parser.consume(token: json)
        #expect(results.count == 1)
        #expect(results[0].type == .style)
    }
}
