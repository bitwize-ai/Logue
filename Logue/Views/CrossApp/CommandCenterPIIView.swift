import SwiftUI

/// Privacy scanner view for the Command Center — scans text for PII
/// using regex + LLM enhancement.
struct CommandCenterPIIView: View {
    let inputText: String
    let onBack: () -> Void
    let onDismiss: () -> Void

    @State private var textToScan: String = ""
    @State private var enabledCategories: Set<PIICategory> = Set(PIICategory.allCases)
    @State private var findings: [PIIFinding] = []
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var hasScanned = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ThinDivider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    categoryToggles
                    ThinDivider().padding(.horizontal, 16)
                    scanButton
                    ThinDivider().padding(.horizontal, 16)
                    resultsSection
                }
            }
        }
        .onAppear {
            // Use input text from prompt bar, or fall back to clipboard
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                textToScan = trimmed
            } else if let clipboard = NSPasteboard.general.string(forType: .string) {
                textToScan = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(AppThemeConstants.opacityLight)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Image(systemName: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppThemeConstants.warning)

            Text("Privacy Scanner")
                .font(AppThemeConstants.islandTitle)
                .foregroundStyle(.primary)

            Spacer()
            DismissCircleButton(action: onDismiss, size: 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Category Toggles

    private var categoryToggles: some View {
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
        .padding(16)
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            scanForPII()
        } label: {
            HStack(spacing: 6) {
                if isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "magnifyingglass")
                }
                Text(isScanning ? "Scanning\u{2026}" : "Scan Text")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .fill(AppThemeConstants.brandPrimary.opacity(
                        isScanning || enabledCategories.isEmpty || textToScan.isEmpty ? 0.4 : 1
                    ))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .disabled(isScanning || enabledCategories.isEmpty || textToScan.isEmpty || LLMEngineStatus.shared.isBusy)
        .accessibilityLabel(isScanning ? "Scanning for personal data" : "Scan text for personal data")
    }

    // MARK: - Results

    private var filteredFindings: [PIIFinding] {
        findings.filter { enabledCategories.contains($0.category) }
    }

    private var groupedFindings: [(PIICategory, [PIIFinding])] {
        let grouped = Dictionary(grouping: filteredFindings, by: \.category)
        return PIICategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    private var highestRisk: PIIRisk {
        let active = filteredFindings
        if active.contains(where: { $0.category.risk == .critical }) {
            return .critical
        }
        if active.contains(where: { $0.category.risk == .high }) {
            return .high
        }
        return .medium
    }

    @ViewBuilder
    private var resultsSection: some View {
        if isScanning {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Analyzing text for personal data\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let error = scanError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppThemeConstants.warning)
                Text("Scan failed")
                    .font(.subheadline.weight(.medium))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 16)
        } else if hasScanned, filteredFindings.isEmpty {
            cleanState
        } else if !hasScanned {
            initialState
        } else {
            summaryBar
                .padding(.horizontal, 16)
                .padding(.top, 12)

            LazyVStack(spacing: 12) {
                ForEach(groupedFindings, id: \.0) { category, items in
                    PIICategoryCard(category: category, findings: items)
                }
            }
            .padding(16)
        }
    }

    private var cleanState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppThemeConstants.brandPrimary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
            }
            Text("No PII detected")
                .font(.subheadline.weight(.medium))
            Text("Your text appears safe to share.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var initialState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppThemeConstants.brandPrimary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "eye.slash")
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
            }
            Text("Scan for personal data")
                .font(.subheadline.weight(.medium))
            Text(textToScan.isEmpty
                ? "Type text in the prompt bar or copy text first, then scan."
                : "Select categories above and scan to detect PII.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    private var summaryBar: some View {
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
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(highestRisk.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .strokeBorder(highestRisk.color.opacity(0.2), lineWidth: 1)
        )
    }

    private func riskCountBadge(count: Int, risk: PIIRisk) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.caption2.weight(.bold))
            Text(risk.rawValue)
                .font(.caption2)
        }
        .foregroundStyle(risk.badgeColor)
    }

    // MARK: - Scan Action

    private func scanForPII() {
        guard !isScanning else { return }
        let text = textToScan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isScanning = true
        scanError = nil
        findings = []

        let enabledCats = enabledCategories
        let scanText = String(text.prefix(6000))

        // Phase 1: Instant regex scan
        let regexFindings = PIIRegexScanner.scan(text: scanText, categories: enabledCats)

        Task {
            // Phase 2: LLM enhancement for contextual PII
            var merged = regexFindings
            do {
                let prompt = buildPIIPrompt(text: String(scanText.prefix(3000)), categories: enabledCats)
                let response = try await LLMEngine.shared.chat(prompt: prompt)
                let llmFindings = parsePIIFindings(from: response, enabled: enabledCats)

                let existingTexts = Set(regexFindings.map { $0.text.lowercased() })
                for finding in llmFindings where !existingTexts.contains(finding.text.lowercased()) {
                    merged.append(finding)
                }
            } catch {
                // Regex results are still valid even if LLM fails
            }

            await MainActor.run {
                findings = merged
                isScanning = false
                hasScanned = true
            }
        }
    }

    private func buildPIIPrompt(text: String, categories: Set<PIICategory>) -> String {
        let categoryList = categories.map { cat in
            "- \(cat.rawValue): \(cat.examples) (Risk: \(cat.risk.rawValue))"
        }.joined(separator: "\n")

        return """
        You are a PII detection expert. Analyze the text and identify ALL personal or sensitive data.

        CATEGORIES:
        \(categoryList)

        RULES:
        - Find every PII instance matching the categories.
        - Return the exact text found and a brief label.
        - Return ONLY valid JSON, no explanation.

        FORMAT:
        {"findings":[{"category":"<exact category name>","text":"<exact text>","detail":"<label>"}]}

        Valid category names: \(categories.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))

        TEXT:
        \(text)
        """
    }

    private func parsePIIFindings(from response: String, enabled: Set<PIICategory>) -> [PIIFinding] {
        let cleaned = extractPIIJSON(from: response)
        guard let data = cleaned.data(using: .utf8) else { return [] }

        struct ScanResponse: Codable { let findings: [PIIFinding] }

        if let scanResponse = try? JSONDecoder().decode(ScanResponse.self, from: data) {
            return scanResponse.findings.filter { enabled.contains($0.category) }
        }
        if let items = try? JSONDecoder().decode([PIIFinding].self, from: data) {
            return items.filter { enabled.contains($0.category) }
        }
        return []
    }

    private func extractPIIJSON(from text: String) -> String {
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

        if let start = result.firstIndex(of: "{"),
           let end = result.lastIndex(of: "}")
        {
            return String(result[start ... end])
        }
        if let start = result.firstIndex(of: "["),
           let end = result.lastIndex(of: "]")
        {
            return String(result[start ... end])
        }
        return result
    }
}
