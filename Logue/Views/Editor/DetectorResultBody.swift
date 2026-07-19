import AppKit
import SwiftUI

/// Phase H: shared rendering for an `AIContentScorer` result. Used inside
/// the document Verify panel's AI Detection sub-tab. Owns its own
/// rewrite state so any caller can drop it in without managing the
/// per-sentence "humanize" button machinery.
///
/// Three sections, top to bottom:
///   1. Probability gauge — overall label + percentage + colored bar.
///   2. AI indicators — chips for the top phrases that triggered.
///   3. Sentence breakdown — per-sentence row with a Rewrite action when
///      the sentence scores ≥ 60 % AI.
struct DetectorResultBody: View {
    let result: DetectorResult

    @State private var rewrittenSentences: [UUID: String] = [:]
    @State private var rewritingSentenceID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            probabilityGauge
            if !result.topIndicators.isEmpty {
                indicatorsSection
            }
            sentencesSection
        }
    }

    // MARK: - Probability gauge

    private var probabilityGauge: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Self.labelColor(result.overallAIProbability))
                Spacer()
                Text("\(Int(result.overallAIProbability * 100))%")
                    .font(.title3.monospacedDigit().weight(.medium))
                    .foregroundStyle(Self.labelColor(result.overallAIProbability))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Self.gaugeGradient)
                        .frame(width: geo.size.width * CGFloat(result.overallAIProbability), height: 8)
                }
            }
            .frame(height: 8)

            Text(result.confidence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private static let gaugeGradient = LinearGradient(
        colors: [.green, .yellow, .orange, .red],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Top indicators

    private var indicatorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Indicators Found")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(result.topIndicators, id: \.self) { phrase in
                    Text(phrase)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.12))
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    // MARK: - Sentence breakdown

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sentence Breakdown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.sentences) { sent in
                    sentenceRow(sent)
                }
            }
        }
    }

    private func sentenceRow(_ sent: DetectorSentenceScore) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.labelColor(sent.aiProbability))
                .frame(width: 4, height: max(20, CGFloat(sent.sentence.count / 6)))

            VStack(alignment: .leading, spacing: 3) {
                if let rewritten = rewrittenSentences[sent.id] {
                    Text(rewritten)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Rewritten — original: \(sent.sentence.prefix(80))…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                } else {
                    Text(sent.sentence)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text("\(Int(sent.aiProbability * 100))% AI")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Self.labelColor(sent.aiProbability))
                    if !sent.foundAIPhrases.isEmpty {
                        Text(sent.foundAIPhrases.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    rewriteButton(for: sent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rewriteButton(for sent: DetectorSentenceScore) -> some View {
        if sent.aiProbability >= 0.60 {
            if rewritingSentenceID == sent.id {
                ProgressView().controlSize(.mini)
            } else if rewrittenSentences[sent.id] != nil {
                Button {
                    rewrittenSentences[sent.id] = nil
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    rewriteSentence(sent)
                } label: {
                    Label("Rewrite", systemImage: "wand.and.stars")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Rewrite this sentence to sound more human-authored")
                .disabled(LLMEngineStatus.shared.isBusy)
            }
        }
    }

    private func rewriteSentence(_ sent: DetectorSentenceScore) {
        rewritingSentenceID = sent.id
        Task {
            let system = "You are an editor. Rewrite the user's sentence so it reads as natural human writing. "
                + "Preserve meaning. Drop AI clichés (\"delve into\", \"in conclusion\", \"furthermore\", "
                + "\"plays a crucial role\", \"navigate the complexities\", etc.). Output ONLY the rewritten "
                + "sentence — no preamble, no quotes, no explanation."
            let user = "<sentence>\n\(sent.sentence)\n</sentence>"
            do {
                let response = try await LLMEngine.shared.complete(system: system, prompt: user)
                let cleaned = response
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                await MainActor.run {
                    rewrittenSentences[sent.id] = cleaned
                    rewritingSentenceID = nil
                }
            } catch {
                await MainActor.run {
                    rewritingSentenceID = nil
                    ToastCenter.shared.show("Rewrite failed", kind: .warning)
                }
            }
        }
    }

    // MARK: - Color helpers

    static func labelColor(_ probability: Float) -> Color {
        switch probability {
        case ..<0.35: .green
        case 0.35 ..< 0.55: .orange
        default: .red
        }
    }
}
