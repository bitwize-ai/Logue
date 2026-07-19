import Foundation

// MARK: - Public Types

/// Parsed markdown table — used as input to `AutoChartView`.
struct ChartTable: Equatable {
    let headers: [String]
    let rows: [[String]]
    /// Column indices that look numeric based on the parser below. The first
    /// entry of `rows` is row 0 — header is separate.
    let numericColumns: [Int]
    /// First "categorical" column (non-numeric, treated as the X-axis label).
    /// Falls back to 0 when every column is numeric.
    let labelColumn: Int
}

/// Chart variants selectable from the Visualize sheet. The inferrer picks one
/// as the default; the user can flip between any compatible variant.
enum AutoChartType: String, CaseIterable, Identifiable {
    case bar
    case pie
    case line
    case scatter

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bar: "Bar"
        case .pie: "Pie"
        case .line: "Line"
        case .scatter: "Scatter"
        }
    }

    var systemImage: String {
        switch self {
        case .bar: "chart.bar.fill"
        case .pie: "chart.pie.fill"
        case .line: "chart.line.uptrend.xyaxis"
        case .scatter: "chart.dots.scatter"
        }
    }
}

// MARK: - ChartTypeInferrer

/// Parses the first markdown table out of a string and decides which chart
/// type to recommend. Mirrors Sidekick's inference rules:
/// - 1 categorical + 1 numeric column → bar (or pie as alternate)
/// - 2+ numeric columns → line (or scatter as alternate)
enum ChartTypeInferrer {
    /// Returns the first GFM-style markdown table found in `markdown`, or nil.
    static func parseFirstTable(from markdown: String) -> ChartTable? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var headerIdx: Int?
        for (idx, line) in lines.enumerated() {
            // Header row: contains a pipe and at least one named cell.
            guard line.contains("|") else { continue }
            // Next line is the alignment separator: at least one segment of `---` or `:---:`.
            let nextIdx = idx + 1
            guard nextIdx < lines.count else { continue }
            let separator = lines[nextIdx].trimmingCharacters(in: .whitespaces)
            if isAlignmentSeparator(separator) {
                headerIdx = idx
                break
            }
        }
        guard let headerIdx else { return nil }

        let headerCells = splitRow(lines[headerIdx])
        guard headerCells.count >= 2 else { return nil }

        // Row scan: from `headerIdx + 2` until we hit a non-pipe line or end.
        var rows: [[String]] = []
        var rowIdx = headerIdx + 2
        while rowIdx < lines.count {
            let trimmed = lines[rowIdx].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !trimmed.contains("|") {
                break
            }
            let cells = splitRow(lines[rowIdx])
            // Pad / truncate so every row has `headerCells.count` columns.
            var normalized = cells
            if normalized.count < headerCells.count {
                normalized.append(contentsOf: Array(repeating: "", count: headerCells.count - normalized.count))
            } else if normalized.count > headerCells.count {
                normalized = Array(normalized.prefix(headerCells.count))
            }
            rows.append(normalized)
            rowIdx += 1
        }
        guard !rows.isEmpty else { return nil }

        // Decide which columns look numeric. A column is numeric if ≥80% of its
        // non-empty cells parse as a number (after stripping common formatting).
        var numericColumns: [Int] = []
        for col in 0 ..< headerCells.count {
            let cells = rows.map { $0[col] }
            let nonEmpty = cells.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !nonEmpty.isEmpty else { continue }
            let parsed = nonEmpty.compactMap(parseNumeric)
            if Double(parsed.count) / Double(nonEmpty.count) >= 0.8 {
                numericColumns.append(col)
            }
        }
        // Need at least one numeric column to be visualizable.
        guard !numericColumns.isEmpty else { return nil }

        let labelColumn = (0 ..< headerCells.count).first { !numericColumns.contains($0) } ?? 0
        return ChartTable(
            headers: headerCells,
            rows: rows,
            numericColumns: numericColumns,
            labelColumn: labelColumn
        )
    }

    /// Default chart type for `table`. Returns nil if the table can't be charted.
    static func suggestType(for table: ChartTable) -> AutoChartType? {
        let numericCount = table.numericColumns.count
        let totalCols = table.headers.count
        guard numericCount >= 1 else { return nil }

        // Case A: exactly 1 numeric + 1 categorical → bar. Pie if every numeric
        // value is non-negative (pie needs non-negative slices).
        if numericCount == 1, totalCols == 2 {
            return .bar
        }

        // Case B: 2+ numeric columns and a categorical → line.
        if numericCount >= 2 {
            return .line
        }

        // Case C: more numeric columns than expected (3+ where total > 2) → bar.
        return .bar
    }

    /// Compatible chart variants for `table`. The Visualize picker uses this so
    /// the user can flip between sensible options without seeing dead ones.
    static func compatibleTypes(for table: ChartTable) -> [AutoChartType] {
        var types: [AutoChartType] = []
        let numericCount = table.numericColumns.count
        let totalCols = table.headers.count

        // Pie / bar: 1 numeric + 1 categorical.
        if numericCount == 1, totalCols == 2 {
            types.append(.bar)
            // Pie needs non-negative numbers.
            let col = table.numericColumns[0]
            let nums = table.rows.compactMap { parseNumeric($0[col]) }
            if !nums.isEmpty, nums.allSatisfy({ $0 >= 0 }) {
                types.append(.pie)
            }
        }

        // Line / scatter: 2+ numeric cols.
        if numericCount >= 2 {
            types.append(.line)
            types.append(.scatter)
            types.append(.bar)
        }

        // Fallback to bar only.
        if types.isEmpty {
            types.append(.bar)
        }

        return Array(NSOrderedSet(array: types)) as? [AutoChartType] ?? types
    }

    /// Strips `%`, `$`, `,`, surrounding whitespace, and parses to Double.
    /// Returns nil if the input doesn't look like a number after cleanup or if
    /// it parses to a non-finite value (NaN, ±Infinity) — non-finite numbers
    /// produce broken Swift Charts axes and silently invisible bars.
    static func parseNumeric(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
        guard !cleaned.isEmpty else { return nil }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    // MARK: - Internals

    /// Splits a markdown table row on `|`, trimming and dropping the leading /
    /// trailing empty cells produced by `| a | b |` syntax.
    private static func splitRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Strip outer pipes if present.
        var working = trimmed
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }
        return working
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `|---|:---:|---|` style separator — at least one segment must be all
    /// dashes (with optional colons for alignment).
    private static func isAlignmentSeparator(_ line: String) -> Bool {
        let segments = splitRow(line)
        guard !segments.isEmpty else { return false }
        for segment in segments where segment.isEmpty {
            continue
        }
        return segments.allSatisfy { segment in
            let inner = segment.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !inner.isEmpty && inner.allSatisfy { $0 == "-" }
        }
    }
}
