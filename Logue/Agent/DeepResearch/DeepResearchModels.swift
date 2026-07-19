import Foundation

// MARK: - DeepResearchStep

/// One step of the 7-step Deep Research pipeline. Drives the progress UI; the
/// `.researching` step is reused across every section (use
/// `DeepResearchCoordinator.currentSectionIdx` for the per-section progress).
enum DeepResearchStep: String, CaseIterable {
    case idle
    case checkingSufficiency
    case synthesizingPrompt
    case planningSections
    case researching
    case writingDraft
    case creatingDiagrams
    case finalizing
    case completed
    case failed

    /// Display label shown in the progress UI.
    var displayLabel: String {
        switch self {
        case .idle: "Ready"
        case .checkingSufficiency: "Checking your prompt"
        case .synthesizingPrompt: "Refining the question"
        case .planningSections: "Planning sections"
        case .researching: "Researching"
        case .writingDraft: "Writing draft"
        case .creatingDiagrams: "Creating diagrams"
        case .finalizing: "Finalizing report"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    /// SF Symbol name used in the step indicator.
    var systemImage: String {
        switch self {
        case .idle: "circle"
        case .checkingSufficiency: "questionmark.circle"
        case .synthesizingPrompt: "wand.and.stars"
        case .planningSections: "list.bullet.indent"
        case .researching: "magnifyingglass"
        case .writingDraft: "doc.text"
        case .creatingDiagrams: "chart.bar.doc.horizontal"
        case .finalizing: "sparkles"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// The strict in-pipeline order; `idle`, `completed`, `failed` are not part
    /// of the working sequence and are excluded from `progressOrder`.
    static let progressOrder: [DeepResearchStep] = [
        .checkingSufficiency,
        .synthesizingPrompt,
        .planningSections,
        .researching,
        .writingDraft,
        .creatingDiagrams,
        .finalizing,
    ]
}

// MARK: - ResearchSection

/// One planned section of the Deep Research report. Populated incrementally:
/// `title` + `description` come from `plan_sections`; `findings` and
/// `sources` come from the per-section research loop.
struct ResearchSection: Identifiable, Hashable {
    let id: UUID
    let title: String
    let description: String
    /// Sections marked `false` skip the research loop and use only the LLM's
    /// general knowledge during `write_draft` (e.g. a "Background" intro).
    let isSearchNeeded: Bool

    /// LLM-summarized findings for this section. Empty until research runs.
    var findings: String
    /// Source URLs referenced during research. Used for the report's `## Sources`
    /// footer + per-claim citations.
    var sources: [URL]

    init(
        id: UUID = .init(),
        title: String,
        description: String,
        isSearchNeeded: Bool,
        findings: String = "",
        sources: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isSearchNeeded = isSearchNeeded
        self.findings = findings
        self.sources = sources
    }
}
