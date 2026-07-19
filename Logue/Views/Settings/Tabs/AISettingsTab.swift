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
    private var disabledToolsRaw: String = ""

    private var disabledTools: Set<String> {
        Set(disabledToolsRaw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static let toolGroups: [(title: String, items: [(String, String)])] = [
        ("Read — meetings & documents", [
            ("list_meetings", "Browse meetings"),
            ("search_meetings", "Keyword search meetings"),
            ("semantic_search_meetings", "Concept search meetings"),
            ("get_meeting_details", "Read a meeting"),
            ("get_transcript", "Read full transcript"),
            ("get_action_items", "Read action items"),
            ("get_daily_digest", "Daily activity digest"),
            ("list_documents", "Browse documents"),
            ("search_documents", "Keyword search documents"),
            ("semantic_search_documents", "Concept search documents"),
            ("get_document", "Read a document"),
        ]),
        ("Write — content", [
            ("create_document", "Create a document"),
            ("update_document", "Edit a document"),
            ("delete_document", "Delete a document"),
            ("move_document", "Move a document"),
            ("add_document_tag", "Tag a document"),
            ("create_space", "Create a space"),
            ("rename_space", "Rename a space"),
            ("delete_space", "Delete a space"),
            ("export_document_pdf", "Export a document as PDF"),
        ]),
        ("Calendar & Reminders", [
            ("get_upcoming_events", "List upcoming events"),
            ("create_calendar_event", "Create event"),
            ("update_calendar_event", "Update event"),
            ("delete_calendar_event", "Delete event"),
            ("get_reminders", "List reminders"),
            ("add_reminder", "Add reminder"),
            ("update_reminder", "Update reminder"),
            ("delete_reminder", "Delete reminder"),
        ]),
        ("AI helpers", [
            ("summarize_document", "Summarize"),
            ("rephrase_text", "Rephrase"),
            ("check_grammar", "Grammar check"),
            ("check_clarity", "Clarity check"),
            ("detect_tone", "Tone detect"),
            ("fact_check_document", "Fact-check"),
            ("detect_pii", "PII detect"),
            ("render_diagram", "Render diagram"),
            ("generate_slides", "Generate slide deck"),
        ]),
        ("Apple-native", [
            ("draft_email", "Draft email in Mail"),
            ("fetch_contacts", "Look up contacts"),
            ("get_location", "Get current location"),
        ]),
        ("Compute & dialogs", [
            ("run_javascript", "Run JavaScript"),
            ("get_confirmation", "Yes/no dialog"),
            ("get_text_input", "Text input dialog"),
            ("get_user_selection", "Pick-one dialog"),
        ]),
        ("Files (Phase G)", [
            ("list_directory", "List directory contents"),
            ("read_file_at_path", "Read file at path"),
            ("write_text_to_file", "Write text to file"),
            ("delete_file_at_path", "Delete file at path"),
        ]),
    ]

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tools", subtitle: "Turn off any tool you don't want the agent to call. Toggling takes effect on the next message.")
            ForEach(Self.toolGroups, id: \.title) { group in
                DisclosureGroup(group.title) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(group.items, id: \.0) { item in
                            toolRow(name: item.0, label: item.1)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
                .font(.callout.weight(.medium))
            }
        }
    }

    private func toolRow(name: String, label: String) -> some View {
        let isEnabled = !disabledTools.contains(name)
        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in setTool(name, enabled: newValue) }
        )) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.switch)
    }

    private func setTool(_ name: String, enabled: Bool) {
        var current = disabledTools
        if enabled {
            current.remove(name)
        } else {
            current.insert(name)
        }
        disabledToolsRaw = current.sorted().joined(separator: ",")
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

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
