import AVFoundation
import SwiftUI

/// Phase A: dedicated tab for agent / chat customization. Houses everything
/// that's specific to Ask Logue rather than the general app — system prompt
/// override, per-tool enable/disable, inference parameter sliders, memory
/// recall thresholds, TTS voice picker, Tavily key + reasoning toggle.
///
/// Each setting writes through `UserDefaults` (or `KeychainHelper` for the
/// Tavily key) and AgentCoordinator picks them up on every send.
struct AISettingsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                systemPromptSection
                Divider()
                toolsSection
                Divider()
                // Right after the built-in tool list, because a server's tools join the same
                // registry and obey the same per-tool switches — putting them in a different
                // tab would suggest they are a different kind of thing.
                MCPServersSection()
                Divider()
                // Next to the tools, because a skill's other half is which tools it narrows
                // to — and the list above is where those names come from.
                SkillsSection()
                Divider()
                inferenceSection
                Divider()
                memorySection
                Divider()
                ttsSection
                Divider()
                webSearchSection
                Divider()
                imageRoutingSection
                Divider()
                knowledgeGraphSection
                Divider()
                reasoningSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - System prompt

    @AppStorage(AppConstants.UserDefaultsKeys.agentSystemPromptOverride)
    private var systemPromptOverride: String = ""

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("System prompt", subtitle: "Replace Logue's default agent instructions. Leave blank to use the built-in prompt.")
            TextEditor(text: $systemPromptOverride)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 220)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            HStack {
                Text(systemPromptOverride.isEmpty ? "Using built-in default" : "Override active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { systemPromptOverride = "" }
                    .controlSize(.small)
                    .disabled(systemPromptOverride.isEmpty)
            }
        }
    }

    // MARK: - Per-tool enable/disable

    @AppStorage(AppConstants.UserDefaultsKeys.disabledAgentTools)
    // Extension-visible: +Tools
    var disabledToolsRaw: String = ""

    // Extension-visible: +Tools
    var disabledTools: Set<String> {
        Set(disabledToolsRaw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    // MARK: - Inference params

    @AppStorage(AppConstants.UserDefaultsKeys.inferenceTemperature)
    private var temperature: Double = -1

    @AppStorage(AppConstants.UserDefaultsKeys.inferenceTopP)
    private var topP: Double = -1

    @AppStorage(AppConstants.UserDefaultsKeys.inferenceMaxTokens)
    private var maxTokens: Int = -1

    private var inferenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Inference", subtitle: "Override sampling parameters. Defaults are good for most cases.")

            inferenceSlider(
                label: "Temperature",
                detail: "Lower = focused, higher = creative",
                value: $temperature,
                range: 0 ... 2,
                step: 0.05,
                defaultValue: -1
            )
            inferenceSlider(
                label: "Top-p",
                detail: "Nucleus sampling cutoff",
                value: $topP,
                range: 0 ... 1,
                step: 0.05,
                defaultValue: -1
            )

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max output tokens").font(.callout.weight(.medium))
                    Text(maxTokens < 0 ? "Default" : "\(maxTokens) tokens")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(
                    value: Binding(
                        get: { maxTokens < 0 ? 2048 : maxTokens },
                        set: { maxTokens = $0 }
                    ),
                    in: 256 ... 8192,
                    step: 256
                ) { EmptyView() }
                if maxTokens >= 0 {
                    Button("Default") { maxTokens = -1 }.controlSize(.small)
                }
            }
        }
    }

    private func inferenceSlider(
        label: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        defaultValue: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.callout.weight(.medium))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value.wrappedValue < 0 ? "Default" : String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                if value.wrappedValue >= 0 {
                    Button("Reset") { value.wrappedValue = defaultValue }.controlSize(.small)
                }
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue < 0 ? range.lowerBound : value.wrappedValue },
                    set: { value.wrappedValue = $0 }
                ),
                in: range,
                step: step
            )
        }
    }

    // MARK: - Memory thresholds

    @AppStorage(AppConstants.UserDefaultsKeys.memoryRecallThreshold)
    private var recallThreshold: Double = 0.6

    @AppStorage(AppConstants.UserDefaultsKeys.memoryTopK)
    private var topK: Int = 5

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory", subtitle: "How aggressively the agent recalls related meetings/documents while answering.")

            inferenceSlider(
                label: "Recall threshold",
                detail: "Only recall snippets above this similarity",
                value: $recallThreshold,
                range: 0.3 ... 0.95,
                step: 0.05,
                defaultValue: 0.6
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top-K").font(.callout.weight(.medium))
                    Text("Maximum recalled snippets per turn")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(value: $topK, in: 1 ... 20) { Text("\(topK)").monospacedDigit() }
            }
        }
    }

    // MARK: - TTS voice

    @AppStorage(AppConstants.UserDefaultsKeys.ttsVoiceIdentifier)
    private var voiceID: String = ""

    private var ttsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Text-to-speech", subtitle: "Voice used by the chat's Read aloud action.")
            Picker("Voice", selection: $voiceID) {
                Text("System default").tag("")
                ForEach(Self.englishVoices(), id: \.identifier) { voice in
                    Text("\(voice.name) — \(voice.language)")
                        .tag(voice.identifier)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Show only English voices (and any user's preferred locale) sorted by
    /// quality. The full system list runs to 500+ voices on macOS — too noisy.
    private static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    // MARK: - Web search

    @AppStorage(AppConstants.UserDefaultsKeys.webSearchEnabled)
    private var webSearchEnabled: Bool = false

    @AppStorage(AppConstants.UserDefaultsKeys.tavilyKeyPresent)
    private var tavilyKeyPresent: Bool = false

    @State private var tavilyDraft: String = ""

    private var webSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "Web search",
                subtitle: "Off by default. When on, the agent can call DuckDuckGo (free) or Tavily (with key)."
            )
            Toggle("Enable web tools", isOn: $webSearchEnabled)
                .toggleStyle(.switch)

            HStack {
                SecureField(
                    tavilyKeyPresent ? "•••• Tavily key saved" : "Optional Tavily API key",
                    text: $tavilyDraft
                )
                .textFieldStyle(.roundedBorder)

                Button(tavilyKeyPresent ? "Replace" : "Save") {
                    saveTavilyKey()
                }
                .disabled(tavilyDraft.isEmpty)

                if tavilyKeyPresent {
                    Button("Clear") { clearTavilyKey() }
                }
            }
            Text(tavilyKeyPresent
                ? "Tavily preferred when web search runs. Falls back to DuckDuckGo if removed."
                : "Without a key, web search uses DuckDuckGo's free HTML endpoint.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            tavilyKeyPresent = Self.readKeychain(Self.tavilyKeychainKey)?.isEmpty == false
        }
    }

    /// Flatten KeychainHelper's `String??` (throws + optional) into `String?`.
    /// Typed-throws compiler can't infer the flatten with `??nil` cleanly and
    /// SwiftLint flags it, so we wrap once and reuse.
    private static func readKeychain(_ key: String) -> String? {
        do {
            return try KeychainHelper.read(key: key)
        } catch {
            return nil
        }
    }

    private static let tavilyKeychainKey = "agent.tavilyAPIKey"

    private func saveTavilyKey() {
        let trimmed = tavilyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainHelper.save(key: Self.tavilyKeychainKey, value: trimmed)
            tavilyKeyPresent = true
            tavilyDraft = ""
            ToastCenter.shared.show(UICopy.Toast.saved)
        } catch {
            ToastCenter.shared.show("Couldn't save key", kind: .warning)
        }
    }

    private func clearTavilyKey() {
        _ = KeychainHelper.delete(key: Self.tavilyKeychainKey)
        tavilyKeyPresent = false
        ToastCenter.shared.show("Cleared")
    }

    // MARK: - Apple Intelligence routing (Phase F)

    @State private var imageRoutingEnabled: Bool = PromptIntentClassifier.shared.isRoutingEnabled

    private var imageRoutingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "Apple Intelligence",
                subtitle: "Route image-generation prompts to ImagePlayground instead of the text agent."
            )
            Toggle("Enable image routing", isOn: $imageRoutingEnabled)
                .toggleStyle(.switch)
                .onChange(of: imageRoutingEnabled) { _, newValue in
                    PromptIntentClassifier.setRoutingEnabled(newValue)
                }
            if imageRoutingEnabled {
                Text("Prompts scored ≥ 70 % image-intent open ImagePlayground. Requires Apple Intelligence on this Mac.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Knowledge Graph

    @State private var graphEnabled: Bool = UserDefaults.standard.bool(forKey: "graph.buildKnowledgeGraph")
    @State private var isRebuildingCommunities = false
    @State private var lastRebuildSummary: String?

    private var knowledgeGraphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "Knowledge Graph",
                subtitle: "After indexing, Logue extracts entities and relationships for cross-meeting recall. Uses inference — off by default."
            )
            Toggle("Build Knowledge Graph", isOn: $graphEnabled)
                .toggleStyle(.switch)
                .onChange(of: graphEnabled) { _, newValue in
                    Task {
                        await EntityExtractor.shared.setEnabled(newValue)
                    }
                }
            if graphEnabled {
                Text(
                    "Entity extraction runs in the background after each meeting or document is indexed."
                        + " Enabling this uses the active model and may take several minutes for large libraries."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        rebuildCommunities()
                    } label: {
                        if isRebuildingCommunities {
                            ProgressView().controlSize(.mini)
                            Text("Rebuilding…")
                        } else {
                            Image(systemName: "circle.hexagongrid.fill")
                            Text("Rebuild communities")
                        }
                    }
                    .controlSize(.small)
                    .disabled(isRebuildingCommunities)
                    if let lastRebuildSummary {
                        Text(lastRebuildSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func rebuildCommunities() {
        isRebuildingCommunities = true
        lastRebuildSummary = nil
        Task {
            let summary = await CommunityDetector.shared.rebuildCommunities()
            await MainActor.run {
                lastRebuildSummary = summary
                isRebuildingCommunities = false
            }
        }
    }

    // MARK: - Reasoning toggle

    @AppStorage(AppConstants.UserDefaultsKeys.showReasoningBlocks)
    private var showReasoning: Bool = false

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Reasoning", subtitle: "Some models emit a <thinking> block before the answer. Off by default.")
            Toggle("Show reasoning blocks in responses", isOn: $showReasoning)
                .toggleStyle(.switch)
        }
    }

    // MARK: - Helpers

    // Extension-visible: +Tools
    func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
