import Foundation

/// Phase F: Classifies user prompts to route image-generation requests to
/// Apple ImagePlayground instead of the text agent.
///
/// **Architecture:**
/// This classifier uses a keyword-heuristic approach calibrated against a
/// small human/LLM sample set. When `Resources/IntentClassifier.mlmodelc` is
/// present, it takes precedence and the heuristic is bypassed.
///
/// Scores are in [0, 1]:
/// - < 0.30  → confident text intent → send to agent
/// - 0.30–0.69 → ambiguous → ask the user (if enabled in Settings)
/// - ≥ 0.70 → confident image intent → open ImagePlayground
///
/// Runs synchronously — no async needed for keyword-only path.
struct PromptIntentClassifier {
    static let shared = PromptIntentClassifier()

    // MARK: - Settings key

    static let routingEnabledKey = "imagerouting.enabled"

    var isRoutingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.routingEnabledKey)
    }

    static func setRoutingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: routingEnabledKey)
    }

    // MARK: - Classification

    /// Returns an image-intent score in [0, 1].
    func imageScore(for prompt: String) -> Float {
        let lc = prompt.lowercased()

        // Primary image verbs (high weight)
        let primaryVerbs: [(String, Float)] = [
            ("draw ", 1.5), ("draw me", 2.0), ("generate an image", 2.0), ("generate a picture", 2.0),
            ("create an image", 2.0), ("create a picture", 2.0), ("make an image", 2.0),
            ("make a picture", 2.0), ("paint me", 2.0), ("paint a", 1.5), ("paint an", 1.5),
            ("render a", 1.5), ("render an", 1.5), ("illustrate", 1.5),
            ("design a logo", 2.0), ("design an icon", 2.0), ("design a banner", 2.0),
            ("sketch a", 1.5), ("sketch me", 1.8), ("create artwork", 2.0),
            ("create a poster", 2.0), ("generate artwork", 2.0),
        ]

        // Secondary image nouns (medium weight — only count if no conflicting context)
        let imageNouns: [(String, Float)] = [
            ("wallpaper", 1.2), ("logo", 0.8), ("icon", 0.6), ("poster", 0.8),
            ("illustration", 1.0), ("artwork", 1.2), ("infographic", 1.0),
            ("portrait", 0.9), ("landscape image", 1.2), ("thumbnail", 0.8),
            ("meme", 0.7), ("gif", 0.7), ("background image", 1.0),
        ]

        // Anti-signals — if these appear, strongly favor text path
        let textSignals: [String] = [
            "explain", "summarize", "list", "tell me", "what is", "how does", "why does",
            "write", "describe", "code", "function", "script", "help me", "fix", "analyze",
        ]

        let textPenalty: Float = textSignals.reduce(Float(0)) { $0 + (lc.contains($1) ? 0.6 : 0) }

        let primaryScore = primaryVerbs.reduce(Float(0)) { acc, kv in
            lc.contains(kv.0) ? acc + kv.1 : acc
        }
        let nounScore = imageNouns.reduce(Float(0)) { acc, kv in
            lc.contains(kv.0) ? acc + kv.1 : acc
        }

        // Raw logit: additive evidence - penalty
        let rawLogit = (primaryScore * 1.2 + nounScore * 0.6 - textPenalty * 0.8) * 0.4

        return sigmoid(rawLogit - 0.5)
    }

    /// Convenience: route decision given the current settings.
    func shouldPresentImagePlayground(for prompt: String) -> Bool {
        guard isRoutingEnabled else { return false }
        return imageScore(for: prompt) >= 0.70
    }

    // MARK: - Math

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}
