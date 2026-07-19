import Charts
import SwiftUI

/// One row's worth of data prepared for charting. `label` is the X-axis category
/// (or scatter label); `values` is the parsed numeric value per numeric column.
struct ChartRow: Identifiable {
    let id = UUID()
    let label: String
    let values: [Double]
}

/// Sheet wrapper for visualizing a parsed markdown table as a Swift Chart.
/// User can flip between compatible chart types via a segmented picker.
struct AutoChartView: View {
    let table: ChartTable
    @State private var chartType: AutoChartType
    @Environment(\.dismiss) private var dismiss

    private let compatibleTypes: [AutoChartType]
    private let preparedRows: [ChartRow]

    init(table: ChartTable) {
        self.table = table
        compatibleTypes = ChartTypeInferrer.compatibleTypes(for: table)
        preparedRows = Self.prepareRows(table: table)
        _chartType = State(initialValue: ChartTypeInferrer.suggestType(for: table) ?? .bar)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chart
                .padding(20)
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visualize Table")
                    .font(.headline)
                Text(table.headers.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if compatibleTypes.count > 1 {
                Picker("", selection: $chartType) {
                    ForEach(compatibleTypes) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        switch chartType {
        case .bar:
            barChart
        case .pie:
            pieChart
        case .line:
            lineChart
        case .scatter:
            scatterChart
        }
    }

    // MARK: - Bar

    @ViewBuilder
    private var barChart: some View {
        let numericIdx = table.numericColumns
        // Single-numeric: simple labelled bars.
        if numericIdx.count == 1 {
            let col = numericIdx[0]
            let header = table.headers[col]
            Chart(preparedRows) { row in
                BarMark(
                    x: .value("Category", row.label),
                    y: .value(header, row.values.first ?? 0)
                )
                .foregroundStyle(AppThemeConstants.brandPrimary)
            }
            .chartLegend(.hidden)
        } else {
            // Multi-numeric: grouped bars per series.
            Chart {
                ForEach(preparedRows) { row in
                    ForEach(Array(numericIdx.enumerated()), id: \.offset) { idx, col in
                        if idx < row.values.count {
                            BarMark(
                                x: .value("Category", row.label),
                                y: .value(table.headers[col], row.values[idx])
                            )
                            .foregroundStyle(by: .value("Series", table.headers[col]))
                            .position(by: .value("Series", table.headers[col]))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pie

    @ViewBuilder
    private var pieChart: some View {
        // Pie uses the first numeric column only.
        let col = table.numericColumns.first ?? 0
        let header = table.headers[col]
        let total = preparedRows.reduce(0.0) { $0 + ($1.values.first ?? 0) }
        if total <= 0 {
            // Sum-to-zero would render an invisible pie. Tell the user instead
            // of silently producing a blank chart.
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text("Pie chart needs at least one positive value.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Try Bar instead.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(preparedRows) { row in
                SectorMark(
                    angle: .value(header, row.values.first ?? 0),
                    innerRadius: .ratio(0.45),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Category", row.label))
            }
        }
    }

    // MARK: - Line

    @ViewBuilder
    private var lineChart: some View {
        let numericIdx = table.numericColumns
        Chart {
            ForEach(preparedRows) { row in
                ForEach(Array(numericIdx.enumerated()), id: \.offset) { idx, col in
                    if idx < row.values.count {
                        LineMark(
                            x: .value("Category", row.label),
                            y: .value(table.headers[col], row.values[idx])
                        )
                        .foregroundStyle(by: .value("Series", table.headers[col]))
                        PointMark(
                            x: .value("Category", row.label),
                            y: .value(table.headers[col], row.values[idx])
                        )
                        .foregroundStyle(by: .value("Series", table.headers[col]))
                    }
                }
            }
        }
    }

    // MARK: - Scatter

    @ViewBuilder
    private var scatterChart: some View {
        // Scatter expects 2+ numeric columns; uses col 0 vs col 1.
        if table.numericColumns.count >= 2 {
            let xCol = table.numericColumns[0]
            let yCol = table.numericColumns[1]
            Chart(preparedRows) { row in
                if row.values.count >= 2 {
                    PointMark(
                        x: .value(table.headers[xCol], row.values[0]),
                        y: .value(table.headers[yCol], row.values[1])
                    )
                    .foregroundStyle(AppThemeConstants.brandPrimary)
                }
            }
        } else {
            Text("Scatter requires at least two numeric columns.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row Prep

    /// Builds `ChartRow`s aligned with the inferrer's numericColumns order.
    /// Rows where every numeric cell fails to parse are dropped to keep the
    /// chart tidy.
    private static func prepareRows(table: ChartTable) -> [ChartRow] {
        var output: [ChartRow] = []
        for row in table.rows {
            let label = row[table.labelColumn]
            let values = table.numericColumns.map { col in
                ChartTypeInferrer.parseNumeric(row[col]) ?? 0
            }
            // Drop rows where every numeric column failed to parse — usually
            // a separator or summary row leaked through.
            let nonZeroParses = table.numericColumns
                .map { col in ChartTypeInferrer.parseNumeric(row[col]) }
                .compactMap { $0 }
            guard !nonZeroParses.isEmpty else { continue }
            output.append(ChartRow(label: label, values: values))
        }
        return output
    }
}
