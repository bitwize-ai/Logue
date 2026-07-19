import Charts
import SwiftUI

/// Shows live CPU and memory usage for the Logue process.
/// Samples every second and displays a 60-second sparkline history.
struct ResourceUsageView: View {
    @State private var monitor = ResourceUsageMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppThemeConstants.paddingXLarge) {
            // Live indicator
            HStack {
                Spacer()
                Circle()
                    .fill(AppThemeConstants.accent)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Metric cards
            HStack(spacing: AppThemeConstants.paddingLarge) {
                MetricCard(
                    title: "CPU",
                    value: String(format: "%.1f%%", monitor.cpuPercent),
                    fraction: min(monitor.cpuPercent / 100, 1),
                    color: gaugeColor(for: monitor.cpuPercent / 100)
                )
                MetricCard(
                    title: "Memory",
                    value: monitor.memoryUsedFormatted,
                    fraction: monitor.memoryFraction,
                    color: gaugeColor(for: monitor.memoryFraction),
                    subtitle: "of \(monitor.totalMemoryFormatted)"
                )
            }

            // Sparklines
            VStack(alignment: .leading, spacing: AppThemeConstants.paddingMedium) {
                SparklineRow(
                    title: "CPU History",
                    values: monitor.cpuHistory,
                    maxValue: 100,
                    color: gaugeColor(for: monitor.cpuPercent / 100),
                    formatValue: { String(format: "%.0f%%", $0) }
                )
                SparklineRow(
                    title: "Memory History",
                    values: monitor.memoryHistory.map { Double($0) },
                    maxValue: Double(monitor.totalMemoryBytes),
                    color: gaugeColor(for: monitor.memoryFraction),
                    formatValue: { _ in monitor.memoryUsedFormatted }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(AppThemeConstants.paddingXXLarge)
        .frame(width: 480, height: 380)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func gaugeColor(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: AppThemeConstants.accent
        case ..<0.8: AppThemeConstants.warning
        default: AppThemeConstants.error
        }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let fraction: Double
    let color: Color
    var subtitle: String?

    var body: some View {
        VStack(spacing: AppThemeConstants.paddingMedium) {
            // Circular gauge
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: fraction)

                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(.callout, design: .monospaced).bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 90, height: 90)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppThemeConstants.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(
                    color: .black.opacity(AppThemeConstants.shadowOpacityDefault),
                    radius: AppThemeConstants.shadowRadiusDefault,
                    y: 2
                )
        )
    }
}

// MARK: - Sparkline Row

private struct SparklineRow: View {
    let title: String
    let values: [Double]
    let maxValue: Double
    let color: Color
    let formatValue: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = values.last {
                    Text(formatValue(last))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(color)
                }
            }

            if values.count > 1 {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, val in
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0 ... max(maxValue, values.max() ?? 1))
                .frame(height: 44)
                .animation(.easeInOut(duration: 0.3), value: values.last)
            } else {
                Rectangle()
                    .fill(color.opacity(0.1))
                    .frame(height: 44)
                    .overlay(
                        Text("Collecting data…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
            }
        }
        .padding(AppThemeConstants.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(
                    color: .black.opacity(AppThemeConstants.shadowOpacityDefault),
                    radius: AppThemeConstants.shadowRadiusDefault,
                    y: 1
                )
        )
    }
}
