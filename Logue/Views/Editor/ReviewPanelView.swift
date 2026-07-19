import SwiftUI

// MARK: - ReviewPanelView

struct ReviewPanelView: View {
    let document: WritingDocument
    var onRunLLMAnalysis: (() -> Void)?
    var onCancelLLMAnalysis: (() -> Void)?
    var onGoalModeChanged: ((WritingGoalMode) -> Void)?
    var isLLMAnalyzing: Bool = false
    var onGradeSave: ((OverallGrade?) -> Void)?
    var onReactionsSave: (([SectionReaction]?) -> Void)?

    @State private var activeTab: ReviewTab = .score
    @State private var isAnalyzing = false
    @State private var analyzeTask: Task<Void, Never>?

    // Score tab state
    @State private var overallGrade: OverallGrade?
    @State private var expandedCategories: Set<RubricCategory> = []
    @State private var scoreError: String?

    // Reactions tab state
    @State private var reactions: [SectionReaction] = []
    @State private var reactionsError: String?

    var body: some View {
        VStack(spacing: 0) {
            topControls
            Divider()
            tabContent
        }
        .background(AppThemeConstants.surfaceBackground)
        .onAppear {
            if overallGrade == nil {
                overallGrade = document.reviewGrade
            }
            if reactions.isEmpty, let saved = document.reviewReactions {
                reactions = saved
            }
        }
        .onDisappear { analyzeTask?.cancel() }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ReviewTab.allCases, id: \.self) { tab in
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

            Menu {
                ForEach(WritingGoalMode.allCases, id: \.self) { mode in
                    Button {
                        onGoalModeChanged?(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: document.goalMode.icon)
                    Text(document.goalMode.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if isAnalyzing || isLLMAnalyzing {
                Button {
                    isAnalyzing = false
                    onCancelLLMAnalysis?()
                } label: {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Cancel")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: analyzeAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Analyze")
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
        case .score: scoreTabContent
        case .reactions: reactionsTabContent
        }
    }

    // MARK: - Analyze All

    private func analyzeAll() {
        isAnalyzing = true
        overallGrade = nil
        reactions = []
        expandedCategories = []
        scoreError = nil
        reactionsError = nil

        // Also trigger LLM proofreading analysis
        onRunLLMAnalysis?()

        analyzeTask = Task {
            async let gradeResult = runGrading()
            async let reactionsResult = runReactions()

            let (gradeRes, reactionsRes) = await (gradeResult, reactionsResult)

            await MainActor.run {
                switch gradeRes {
                case let .success(grade):
                    overallGrade = grade
                    onGradeSave?(grade)
                case let .failure(error): scoreError = error.localizedDescription
                }
                switch reactionsRes {
                case let .success(result):
                    reactions = result
                    onReactionsSave?(result)
                case let .failure(error): reactionsError = error.localizedDescription
                }
                isAnalyzing = false
            }
        }
    }
}

// MARK: - Score Tab

extension ReviewPanelView {
    private var scoreTabContent: some View {
        Group {
            if let error = scoreError {
                errorView(error)
            } else if isAnalyzing, overallGrade == nil {
                loadingView("Grading your writing…")
            } else if let grade = overallGrade {
                scoreResultsView(grade)
            } else {
                emptyView(icon: "graduationcap", title: "No grade yet", subtitle: "Get comprehensive scoring with detailed feedback")
            }
        }
    }

    private func scoreResultsView(_ grade: OverallGrade) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                overallGradeCard(grade)

                VStack(spacing: 10) {
                    ForEach(grade.grades) { categoryGrade in
                        CategoryGradeCard(
                            grade: categoryGrade,
                            isExpanded: expandedCategories.contains(categoryGrade.category),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedCategories.contains(categoryGrade.category) {
                                        expandedCategories.remove(categoryGrade.category)
                                    } else {
                                        expandedCategories.insert(categoryGrade.category)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(AppThemeConstants.paddingLarge)
        }
    }

    private func overallGradeCard(_ grade: OverallGrade) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Overall Grade")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                Text(grade.letterGrade)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(letterGradeColor(grade.letterGrade))

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(grade.averageScore)/100")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(scoreColor(grade.averageScore))

                    ProgressView(value: Double(grade.averageScore), total: 100)
                        .tint(scoreColor(grade.averageScore))

                    Text(grade.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(AppThemeConstants.paddingLarge)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXLarge))
    }
}

// MARK: - Reactions Tab

extension ReviewPanelView {
    private var reactionsTabContent: some View {
        Group {
            if let error = reactionsError {
                errorView(error)
            } else if isAnalyzing, reactions.isEmpty {
                loadingView("Analyzing reactions…")
            } else if reactions.isEmpty {
                emptyView(icon: "person.2", title: "No reactions yet", subtitle: "Predict how readers will emotionally respond")
            } else {
                List {
                    ForEach(reactions) { reaction in
                        SectionReactionCard(reaction: reaction)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Shared UI

private extension ReviewPanelView {
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
            Button(action: analyzeAll) {
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
}

// MARK: - LLM Calls & Parsing

private extension ReviewPanelView {
    func runGrading() async -> Result<OverallGrade, Error> {
        let prompt = """
        Grade this writing using a comprehensive rubric with these categories:
        1. Thesis (central argument)
        2. Evidence (supporting details)
        3. Organization (structure and flow)
        4. Style (voice and engagement)
        5. Grammar (technical correctness)
        6. Clarity (readability)

        For each category, provide:
        - Score (0-100)
        - Letter grade
        - Feedback
        - Strengths
        - Areas for improvement

        Return ONLY valid JSON in this exact format:
        {
          "summary": "Overall summary of the text assessment...",
          "grades": [
            {
              "category": "Thesis",
              "score": 90,
              "letterGrade": "A-",
              "feedback": "Feedback for thesis...",
              "strengths": ["Strength 1"],
              "improvements": ["Improvement 1"]
            }
          ]
        }

        Category strings must be exactly: Thesis, Evidence, Organization, Style, Grammar, Clarity.

        <content>
        \(String(document.body.prefix(LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens))))
        </content>
        """

        do {
            let grade = try await withRetry {
                let response = try await LLMEngine.shared.chat(prompt: prompt)
                guard let parsed = self.parseGrade(response) else {
                    throw NSError(domain: "ReviewPanel", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse grade results."])
                }
                return parsed
            }
            return .success(grade)
        } catch {
            return .failure(error)
        }
    }

    func runReactions() async -> Result<[SectionReaction], Error> {
        let prompt = """
        Analyze this text and predict reader emotional responses for different sections.
        Return ONLY valid JSON in this exact format:
        [
          {
            "sectionTitle": "Section Name",
            "dominantEmotion": "engaged",
            "emotionScores": {"engaged": 85, "excited": 60, "confused": 15},
            "explanation": "Why readers feel this way"
          }
        ]

        Emotions must be from: excited, confused, skeptical, engaged, bored, inspired.
        Scores are 0-100. Break the text into 3-5 sections.

        <content>
        \(String(document.body.prefix(LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens))))
        </content>
        """

        do {
            let reactions = try await withRetry {
                let response = try await LLMEngine.shared.chat(prompt: prompt)
                let parsed = self.parseReactions(response)
                guard !parsed.isEmpty else {
                    throw NSError(domain: "ReviewPanel", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse reaction results."])
                }
                return parsed
            }
            return .success(reactions)
        } catch {
            return .failure(error)
        }
    }

    func parseGrade(_ text: String) -> OverallGrade? {
        guard let jsonStart = text.firstIndex(of: "{"),
              let jsonEnd = text.lastIndex(of: "}"),
              jsonStart < jsonEnd
        else { return nil }

        let jsonString = String(text[jsonStart ... jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let summary = json["summary"] as? String ?? "Detailed assessment completed."
        guard let gradesArray = json["grades"] as? [[String: Any]] else { return nil }

        var grades: [Grade] = []
        for item in gradesArray {
            guard let catStr = item["category"] as? String,
                  let score = item["score"] as? Int,
                  let letterGrade = item["letterGrade"] as? String,
                  let feedback = item["feedback"] as? String
            else { continue }

            let category: RubricCategory
            switch catStr.lowercased() {
            case "thesis": category = .thesis
            case "evidence": category = .evidence
            case "organization": category = .organization
            case "style": category = .style
            case "grammar": category = .grammar
            case "clarity": category = .clarity
            default: continue
            }

            grades.append(Grade(
                category: category,
                score: score,
                letterGrade: letterGrade,
                feedback: feedback,
                strengths: item["strengths"] as? [String] ?? [],
                improvements: item["improvements"] as? [String] ?? []
            ))
        }

        if grades.isEmpty {
            return nil
        }
        let averageScore = grades.map(\.score).reduce(0, +) / grades.count
        return OverallGrade(averageScore: averageScore, letterGrade: scoreToLetter(averageScore), summary: summary, grades: grades)
    }

    func parseReactions(_ text: String) -> [SectionReaction] {
        guard let arrayStart = text.firstIndex(of: "["),
              let arrayEnd = text.lastIndex(of: "]"),
              arrayStart < arrayEnd
        else { return [] }

        let jsonString = String(text[arrayStart ... arrayEnd])
        guard let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> SectionReaction? in
            guard let sectionTitle = item["sectionTitle"] as? String,
                  let emotionStr = item["dominantEmotion"] as? String,
                  let explanation = item["explanation"] as? String
            else { return nil }

            let dominantEmotion = emotionFromString(emotionStr) ?? .engaged
            var emotionScores: [EmotionType: Int] = [:]
            if let scores = item["emotionScores"] as? [String: Any] {
                for (key, value) in scores {
                    if let emotion = emotionFromString(key), let score = value as? Int {
                        emotionScores[emotion] = min(max(score, 0), 100)
                    }
                }
            }
            if emotionScores.isEmpty {
                emotionScores[dominantEmotion] = 80
            }
            return SectionReaction(
                sectionTitle: sectionTitle,
                sectionText: "",
                dominantEmotion: dominantEmotion,
                emotionScores: emotionScores,
                explanation: explanation
            )
        }
    }

    func emotionFromString(_ string: String) -> EmotionType? {
        switch string.lowercased() {
        case "excited": .excited
        case "confused": .confused
        case "skeptical": .skeptical
        case "engaged": .engaged
        case "bored": .bored
        case "inspired": .inspired
        default: nil
        }
    }

    func scoreToLetter(_ score: Int) -> String {
        if score >= 97 {
            return "A+"
        }
        if score >= 93 {
            return "A"
        }
        if score >= 90 {
            return "A-"
        }
        if score >= 87 {
            return "B+"
        }
        if score >= 83 {
            return "B"
        }
        if score >= 80 {
            return "B-"
        }
        if score >= 77 {
            return "C+"
        }
        if score >= 73 {
            return "C"
        }
        if score >= 70 {
            return "C-"
        }
        return "D"
    }

    func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return AppThemeConstants.success
        }
        if score >= 80 {
            return AppThemeConstants.brandPrimary
        }
        if score >= 70 {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.error
    }

    func letterGradeColor(_ letter: String) -> Color {
        if letter.starts(with: "A") {
            return AppThemeConstants.success
        }
        if letter.starts(with: "B") {
            return AppThemeConstants.brandPrimary
        }
        if letter.starts(with: "C") {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.error
    }
}
