import SwiftUI

// MARK: - VerifyPanelView

struct VerifyPanelView: View {
    let document: WritingDocument
    var onFactChecksSave: (([FactCheck]?) -> Void)?
    var onPIIFindingsSave: (([PIIFinding]?) -> Void)?
    var onAIDetectionSave: ((DetectorResult?) -> Void)?

    @State private var activeTab: VerifyTab = .facts
    @State private var isVerifying = false

    // Facts tab state
    @State private var factChecks: [FactCheck] = []
    @State private var factsError: String?
    @State private var selectedStatus: Set<FactStatus> = [.verified, .unverified, .uncertain, .misleading]

    // Privacy tab state
    @State private var findings: [PIIFinding] = []
    @State private var privacyError: String?
    @State private var enabledCategories: Set<PIICategory> = Set(PIICategory.allCases)
    @State private var hasScanned = false

    // AI Detection tab state (Phase H)
    @State private var aiDetectionResult: DetectorResult?
    @State private var aiDetectionError: String?

    var body: some View {
        VStack(spacing: 0) {
            topControls
            Divider()
            tabContent
        }
        .background(AppThemeConstants.surfaceBackground)
        .onAppear {
            if factChecks.isEmpty, let saved = document.factChecks {
                factChecks = saved; hasScanned = true
            }
            if findings.isEmpty, let saved = document.piiFindings {
                findings = saved; hasScanned = true
            }
            // Phase H: rehydrate AI Detection result from the document.
            if aiDetectionResult == nil,
               let raw = document.aiDetectionResult, !raw.isEmpty,
               let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(DetectorResult.self, from: data)
            {
                aiDetectionResult = decoded
            }
        }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(VerifyTab.allCases, id: \.self) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: activeTab.icon)
                    Text(activeTab.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if isVerifying {
                Button {
                    isVerifying = false
                } label: {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Cancel")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: verifyAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.small)
                .disabled(document.body.isEmpty || LLMEngineStatus.shared.isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .facts: factsTabContent
        case .privacy: privacyTabContent
        case .aiDetection: aiDetectionTabContent
        }
    }

    // MARK: - Verify All

    private func verifyAll() {
        isVerifying = true
        factChecks = []
        findings = []
        aiDetectionResult = nil
        factsError = nil
        privacyError = nil
        aiDetectionError = nil

        let enabledCats = enabledCategories
        let docText = document.body

        Task {
            async let factsResult = runFactCheck(text: docText)
            async let privacyResult = runPrivacyScan(text: docText, categories: enabledCats)
            async let aiResult: DetectorResult = AIContentScorer.shared.score(text: docText)

            let (factsRes, privacyRes, aiRes) = await (factsResult, privacyResult, aiResult)

            await MainActor.run {
                switch factsRes {
                case let .success(checks):
                    factChecks = checks
                    onFactChecksSave?(checks)
                case let .failure(error): factsError = error.localizedDescription
                }
                switch privacyRes {
                case let .success(items):
                    findings = items
                    onPIIFindingsSave?(items)
                case let .failure(error): privacyError = error.localizedDescription
                }
                aiDetectionResult = aiRes
                onAIDetectionSave?(aiRes)
                hasScanned = true
                isVerifying = false
            }
        }
    }
}

// MARK: - AI Detection Tab (Phase H)

private extension VerifyPanelView {
    var aiDetectionTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = aiDetectionError {
                    errorView(error)
                } else if isVerifying, aiDetectionResult == nil {
                    loadingView("Analyzing for AI patterns…")
                } else if let result = aiDetectionResult {
                    DetectorResultBody(result: result)
                        .padding(AppThemeConstants.paddingLarge)
                } else {
                    emptyView(
                        icon: "waveform.badge.magnifyingglass",
                        title: "No analysis yet",
                        subtitle: "Press Verify to estimate how AI-authored this document looks. " +
                            "Heuristic only — phrase density, burstiness, vocabulary diversity."
                    )
                }
            }
        }
    }
}

// MARK: - Facts Tab

private extension VerifyPanelView {
    var filteredFactChecks: [FactCheck] {
        factChecks.filter { selectedStatus.contains($0.status) }
    }

    var statusCounts: [FactStatus: Int] {
        Dictionary(grouping: factChecks, by: { $0.status }).mapValues { $0.count }
    }

    var factsTabContent: some View {
        VStack(spacing: 0) {
            if !factChecks.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([FactStatus.verified, .unverified, .uncertain, .misleading], id: \.self) { status in
                            StatusFilterChip(
                                status: status,
                                count: statusCounts[status] ?? 0,
                                isSelected: selectedStatus.contains(status),
                                onToggle: {
                                    if selectedStatus.contains(status) {
                                        selectedStatus.remove(status)
                                    } else {
                                        selectedStatus.insert(status)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
            }

            if let error = factsError {
                errorView(error)
            } else if isVerifying, factChecks.isEmpty {
                loadingView("Checking facts…")
            } else if factChecks.isEmpty {
                emptyView(icon: "scalemass", title: "No fact checks yet", subtitle: "Verify factual claims in your writing")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            factsSummaryBadge(.verified)
                            factsSummaryBadge(.uncertain)
                            factsSummaryBadge(.misleading)
                            Spacer()
                            Text("\(filteredFactChecks.count)/\(factChecks.count)")
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        LazyVStack(spacing: 0) {
                            ForEach(filteredFactChecks) { factCheck in
                                FactCheckCard(factCheck: factCheck)
                                    .padding(.horizontal, 16)
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Privacy Tab

private extension VerifyPanelView {
    var filteredFindings: [PIIFinding] {
        findings.filter { enabledCategories.contains($0.category) }
    }

    var groupedFindings: [(PIICategory, [PIIFinding])] {
        let grouped = Dictionary(grouping: filteredFindings, by: \.category)
        return PIICategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var highestRisk: PIIRisk {
        let active = filteredFindings
        if active.contains(where: { $0.category.risk == .critical }) {
            return .critical
        }
        if active.contains(where: { $0.category.risk == .high }) {
            return .high
        }
        return .medium
    }

    var privacyTabContent: some View {
        VStack(spacing: 0) {
            if !findings.isEmpty {
                HStack {
                    Spacer()
                    riskBadge(for: highestRisk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            ScrollView {
                VStack(spacing: 0) {
                    categoryToggles
                    Divider().padding(.horizontal, 16)
                    privacyResults
                }
            }
        }
    }

    var categoryToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(enabledCategories.count == PIICategory.allCases.count ? "Deselect all" : "Select all") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if enabledCategories.count == PIICategory.allCases.count {
                            enabledCategories.removeAll()
                        } else {
                            enabledCategories = Set(PIICategory.allCases)
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(AppThemeConstants.brandPrimary)
            }

            FlowLayout(spacing: 6) {
                ForEach(PIICategory.allCases) { category in
                    CategoryBadge(
                        category: category,
                        isEnabled: enabledCategories.contains(category),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if enabledCategories.contains(category) {
                                    enabledCategories.remove(category)
                                } else {
                                    enabledCategories.insert(category)
                                }
                            }
                        }
                    )
                }
            }
        }
        .padding(AppThemeConstants.paddingLarge)
    }

    @ViewBuilder
    var privacyResults: some View {
        if isVerifying {
            VStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                Text("Analyzing document for personal data…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let error = privacyError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(AppThemeConstants.warning)
                Text("Scan failed").font(.subheadline.weight(.medium))
                Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 16)
        } else if hasScanned, filteredFindings.isEmpty {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(AppThemeConstants.brandPrimary.opacity(0.12)).frame(width: 56, height: 56)
                    Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(AppThemeConstants.brandPrimary)
                }
                Text("No PII detected").font(.subheadline.weight(.medium))
                Text("Your document appears safe to share.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if !hasScanned {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(AppThemeConstants.brandPrimary.opacity(0.12)).frame(width: 56, height: 56)
                    Image(systemName: "eye.slash").font(.title2).foregroundStyle(AppThemeConstants.brandPrimary)
                }
                Text("Scan for personal data").font(.subheadline.weight(.medium))
                Text("Select categories above and press Verify Content.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 16)
        } else {
            summaryBar.padding(.horizontal, 16).padding(.top, 12)
            LazyVStack(spacing: 12) {
                ForEach(groupedFindings, id: \.0) { category, items in
                    PIICategoryCard(category: category, findings: items)
                }
            }
            .padding(AppThemeConstants.paddingLarge)
        }
    }

    var summaryBar: some View {
        HStack(spacing: 12) {
            Label("\(filteredFindings.count) found", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(highestRisk.color)
            Spacer()
            let critCount = filteredFindings.filter { $0.category.risk == .critical }.count
            let highCount = filteredFindings.filter { $0.category.risk == .high }.count
            let medCount = filteredFindings.filter { $0.category.risk == .medium }.count
            if critCount > 0 {
                riskCountBadge(count: critCount, risk: .critical)
            }
            if highCount > 0 {
                riskCountBadge(count: highCount, risk: .high)
            }
            if medCount > 0 {
                riskCountBadge(count: medCount, risk: .medium)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium).fill(highestRisk.color.opacity(AppThemeConstants.opacityLight)))
        .overlay(RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium).strokeBorder(
            highestRisk.color.opacity(AppThemeConstants.opacityMedium),
            lineWidth: 1
        ))
    }
}

// MARK: - LLM Calls & Parsing

private extension VerifyPanelView {
    func runFactCheck(text: String) async -> Result<[FactCheck], Error> {
        let prompt = PromptRegistry.Verification.factCheckPrompt(text: text)

        do {
            let checks = try await withRetry {
                let response = try await LLMEngine.shared.chat(prompt: prompt)
                let parsed = self.parseFactChecks(response)
                guard !parsed.isEmpty else {
                    throw NSError(domain: "VerifyPanel", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse fact check results."])
                }
                return parsed
            }
            return .success(checks)
        } catch {
            return .failure(error)
        }
    }

    func runPrivacyScan(text: String, categories: Set<PIICategory>) async -> Result<[PIIFinding], Error> {
        let docText = String(text.prefix(6000))
        let regexFindings = PIIRegexScanner.scan(text: docText, categories: categories)
        var merged = regexFindings
        do {
            let (systemPrompt, userPrompt) = buildPIIPrompt(text: String(docText.prefix(3000)), categories: categories)
            let response = try await LLMEngine.shared.complete(system: systemPrompt, prompt: userPrompt)
            let llmFindings = parsePIIFindings(from: response, enabled: categories)
            let existingTexts = Set(regexFindings.map { $0.text.lowercased() })
            for finding in llmFindings where !existingTexts.contains(finding.text.lowercased()) {
                merged.append(finding)
            }
        } catch {
            // Regex results still valid even if LLM fails
        }
        return .success(merged)
    }

    func parseFactChecks(_ text: String) -> [FactCheck] {
        // Strip markdown fences but do NOT use extractJSON (it prefers {} over [])
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let arrayStart = cleaned.firstIndex(of: "[") else { return [] }

        var jsonString: String
        if let arrayEnd = cleaned.lastIndex(of: "]"), arrayStart < arrayEnd {
            jsonString = String(cleaned[arrayStart ... arrayEnd])
        } else {
            // Truncated JSON — try to repair by closing open brackets
            jsonString = String(cleaned[arrayStart...])
            jsonString = repairTruncatedJSON(jsonString) ?? jsonString
        }

        guard let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> FactCheck? in
            guard let claim = item["claim"] as? String,
                  let statusStr = item["status"] as? String,
                  let explanation = item["explanation"] as? String
            else { return nil }

            let status: FactStatus = switch statusStr.lowercased() {
            case "verified": .verified
            case "unverified": .unverified
            case "uncertain": .uncertain
            case "misleading": .misleading
            default: .uncertain
            }

            return FactCheck(
                claim: claim,
                status: status,
                explanation: explanation,
                sources: item["sources"] as? [String] ?? [],
                confidence: min(max(item["confidence"] as? Int ?? 50, 0), 100)
            )
        }
    }

    func buildPIIPrompt(text: String, categories: Set<PIICategory>) -> (system: String, user: String) {
        let system = PromptRegistry.Verification.piiSystemPrompt(categories: categories)
        let user = "TEXT:\n\(text)"
        return (system, user)
    }

    func parsePIIFindings(from response: String, enabled: Set<PIICategory>) -> [PIIFinding] {
        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        if let scanResponse = try? JSONDecoder().decode(PIIScanResponse.self, from: data) {
            return scanResponse.findings.filter { enabled.contains($0.category) }
        }
        if let items = try? JSONDecoder().decode([PIIFinding].self, from: data) {
            return items.filter { enabled.contains($0.category) }
        }
        return []
    }

    func extractJSON(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = result.firstIndex(of: "{"), let end = result.lastIndex(of: "}") {
            return String(result[start ... end])
        }
        if let start = result.firstIndex(of: "["), let end = result.lastIndex(of: "]") {
            return String(result[start ... end])
        }
        // Return as-is if no complete brackets found (may be truncated)
        return result
    }

    func repairTruncatedJSON(_ json: String) -> String? {
        var candidate = json
        while !candidate.isEmpty {
            var objDepth = 0
            var arrDepth = 0
            var inStr = false
            var prev: Character = " "

            for char in candidate {
                if char == "\"", prev != "\\" {
                    inStr.toggle()
                }
                if !inStr {
                    if char == "{" {
                        objDepth += 1
                    }
                    if char == "}" {
                        objDepth -= 1
                    }
                    if char == "[" {
                        arrDepth += 1
                    }
                    if char == "]" {
                        arrDepth -= 1
                    }
                }
                prev = char
            }

            if inStr {
                if let lastQuote = candidate.lastIndex(of: "\"") {
                    candidate = String(candidate[..<lastQuote])
                    continue
                }
            }

            var repaired = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if repaired.hasSuffix(",") {
                repaired = String(repaired.dropLast())
            }
            for _ in 0 ..< objDepth {
                repaired += "}"
            }
            for _ in 0 ..< arrDepth {
                repaired += "]"
            }

            if let data = repaired.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil
            {
                return repaired
            }

            if let lastBrace = candidate.lastIndex(of: "}") {
                candidate = String(candidate[...lastBrace])
            } else {
                break
            }
        }
        return nil
    }
}

// MARK: - Shared UI Helpers

private extension VerifyPanelView {
    func loadingView(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.medium))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(AppThemeConstants.error)
            Text("Analysis Failed").font(.subheadline.weight(.medium))
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
            Button(action: verifyAll) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func riskBadge(for risk: PIIRisk) -> some View {
        Text(risk.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(risk.badgeColor.opacity(AppThemeConstants.opacityMedium), in: Capsule())
            .foregroundStyle(risk.badgeColor)
    }

    func riskCountBadge(count: Int, risk: PIIRisk) -> some View {
        HStack(spacing: 3) {
            Text("\(count)").font(.caption2.weight(.bold))
            Text(risk.rawValue).font(.caption2)
        }
        .foregroundStyle(risk.badgeColor)
    }

    @ViewBuilder
    func factsSummaryBadge(_ status: FactStatus) -> some View {
        let count = statusCounts[status] ?? 0
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: status.icon)
                    .font(.system(size: 8))
                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(status.color)
        }
    }
}
