import AppKit
import Foundation

// MARK: - Suggestion

/// A single writing correction or improvement suggestion.
struct Suggestion: Identifiable, Sendable {
    let id: UUID
    let type: SuggestionType
    /// The exact substring in the original text to be replaced.
    let original: String
    /// The corrected or improved replacement text.
    let replacement: String
    /// One-sentence human-readable explanation shown in the suggestion panel.
    let explanation: String
    /// Model confidence in this suggestion (0.0 – 1.0).
    let confidence: Double
    /// Character range of `original` within the full analysed text.
    /// Spell-check suggestions set this immediately; LLM suggestions resolve it during underline rendering.
    var textRange: NSRange
}

// MARK: - SuggestionType

enum SuggestionType: String, Codable, Sendable, CaseIterable {
    case grammar
    case spelling
    case punctuation
    case style
    case clarity
    case tone
    case conciseness

    var displayName: String {
        switch self {
        case .grammar: "Grammar"
        case .spelling: "Spelling"
        case .punctuation: "Punctuation"
        case .style: "Style"
        case .clarity: "Clarity"
        case .tone: "Tone"
        case .conciseness: "Conciseness"
        }
    }

    /// Tier for suggestion hierarchy:
    /// 1 = word-level (spelling), 2 = grammar/auxiliary, 3 = sentence-level (LLM).
    var tier: Int {
        switch self {
        case .spelling: 1
        case .grammar, .punctuation: 2
        case .style, .tone, .clarity, .conciseness: 3
        }
    }

    /// Category-level display name matching the sidebar tabs.
    var categoryDisplayName: String {
        if isCorrectness {
            return "Correctness"
        }
        if isClarity {
            return "Clarity"
        }
        if isDelivery {
            return "Delivery"
        }
        return "Correctness"
    }

    /// SwiftUI color for badge and suggestion card accents.
    var swiftUIColor: Color {
        switch self {
        case .spelling: AppThemeConstants.error // Tier 1: red
        case .grammar, .punctuation: AppThemeConstants.warning // Tier 2: orange
        case .style, .tone: AppThemeConstants.info // Tier 3: blue
        case .clarity, .conciseness: AppThemeConstants.success // Tier 3: green
        }
    }

    /// Color matching the category tab (Correctness/Clarity/Delivery).
    var categoryColor: Color {
        if isCorrectness {
            return AppThemeConstants.error
        }
        if isClarity {
            return AppThemeConstants.brandPrimary
        }
        if isDelivery {
            return AppThemeConstants.categoryPurple
        }
        return AppThemeConstants.error
    }

    /// NSColor for NSLayoutManager underline decorations in the editor.
    var nsColor: NSColor {
        switch self {
        case .spelling: .systemRed // Tier 1: red
        case .grammar, .punctuation: .systemOrange // Tier 2: orange
        case .style, .tone: .systemBlue // Tier 3: blue
        case .clarity, .conciseness: .systemGreen // Tier 3: green
        }
    }

    /// NSColor matching the category tab (Correctness/Clarity/Delivery) for editor underlines.
    var nsCategoryColor: NSColor {
        if isCorrectness {
            return .systemRed
        }
        if isClarity {
            return NSColor(AppThemeConstants.brandPrimary)
        }
        if isDelivery {
            return NSColor(AppThemeConstants.categoryPurple)
        }
        return .systemRed
    }

    /// Whether this type falls in the Correctness category.
    var isCorrectness: Bool {
        [.grammar, .spelling, .punctuation].contains(self)
    }

    /// Whether this type falls in the Clarity category.
    var isClarity: Bool {
        [.clarity, .conciseness].contains(self)
    }

    /// Whether this type falls in the Delivery category.
    var isDelivery: Bool {
        [.tone, .style].contains(self)
    }
}

// MARK: - LLM JSON Codable types

/// The JSON structure the LLM is instructed to return.
struct SuggestionResponse: Codable {
    let suggestions: [SuggestionItem]

    struct SuggestionItem: Codable, Sendable {
        let type: String
        let original: String
        let replacement: String
        let explanation: String
        let confidence: Double

        func toDomain() -> Suggestion {
            Suggestion(
                id: UUID(),
                type: SuggestionType(rawValue: type) ?? .style,
                original: original,
                replacement: replacement,
                explanation: explanation,
                confidence: confidence,
                textRange: NSRange(location: NSNotFound, length: 0)
            )
        }
    }
}

// MARK: - SwiftUI Color import shim

import SwiftUI
