import Foundation
import os.log

/// Extracted from LLMEngine to separate parsing concerns from inference.
/// All methods are static and nonisolated — safe to call from any context.
enum LLMResponseParser {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "LLMResponseParser")

    /// Parses a JSON response from the LLM into suggestion items.
    /// Handles LLM preamble text before the JSON object.
    static func parseSuggestionItems(from rawOutput: String) -> [SuggestionResponse.SuggestionItem] {
        guard let jsonStart = rawOutput.firstIndex(of: "{") else {
            logger.warning("parseSuggestionItems: no JSON found in output (\(rawOutput.count) chars)")
            return []
        }
        let jsonString = String(rawOutput[jsonStart...])
        guard let data = jsonString.data(using: .utf8) else { return [] }
        do {
            let response = try JSONDecoder().decode(SuggestionResponse.self, from: data)
            return response.suggestions
        } catch {
            logger.warning("parseSuggestionItems decode failed: \(String(describing: error), privacy: .public)")
            logger.debug("Raw output prefix: \(String(rawOutput.prefix(500)), privacy: .private)")
            return []
        }
    }

    /// Parses a JSON tone detection result from the LLM.
    static func parseToneResult(from rawOutput: String) -> ToneResult {
        guard let jsonStart = rawOutput.firstIndex(of: "{"),
              let data = String(rawOutput[jsonStart...]).data(using: .utf8)
        else {
            logger.warning("parseToneResult: no JSON found in output (\(rawOutput.count) chars)")
            return .neutral
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tone = json["tone"] as? String,
                  let score = json["score"] as? Double
            else {
                logger.warning("parseToneResult: missing 'tone' or 'score' fields")
                logger.debug("Raw output prefix: \(String(rawOutput.prefix(500)), privacy: .private)")
                return .neutral
            }
            return ToneResult(label: tone, confidence: score)
        } catch {
            logger.warning("parseToneResult decode failed: \(String(describing: error), privacy: .public)")
            logger.debug("Raw output prefix: \(String(rawOutput.prefix(500)), privacy: .private)")
            return .neutral
        }
    }
}
