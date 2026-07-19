import SwiftUI

/// Compact progress strip shown above the agent input bar while a Deep Research
/// run is in flight. Lists the 7 pipeline steps with a checkmark for completed,
/// a spinner for in-progress, and an empty circle for pending. Includes a Cancel
/// button so the user isn't stranded.
struct DeepResearchProgressView: View {
    @State private var coordinator = DeepResearchCoordinator.shared

    var body: some View {
        if coordinator.isRunning || coordinator.currentStep == .failed {
            VStack(alignment: .leading, spacing: 10) {
                header
                stepList
                if coordinator.currentStep == .researching, !coordinator.sections.isEmpty {
                    sectionProgress
                }
                if coordinator.currentStep == .failed, let err = coordinator.lastError {
                    errorRow(err)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(AppThemeConstants.brandPrimary)
            Text("Deep Research")
                .font(.callout)
                .fontWeight(.semibold)
            Spacer()
            if coordinator.isRunning {
                Button("Cancel") {
                    coordinator.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
            } else {
                Button {
                    coordinator.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
    }

    // MARK: - Step list

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(DeepResearchStep.progressOrder, id: \.self) { step in
                stepRow(step)
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: DeepResearchStep) -> some View {
        let state = stateFor(step)
        HStack(spacing: 8) {
            switch state {
            case .pending:
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .active:
                ProgressView()
                    .controlSize(.mini)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.brandPrimary)
            }
            Text(step.displayLabel)
                .font(.caption)
                .foregroundStyle(state == .pending ? .tertiary : .primary)
        }
    }

    private enum StepState { case pending, active, done }

    private func stateFor(_ step: DeepResearchStep) -> StepState {
        let order = DeepResearchStep.progressOrder
        guard let stepIdx = order.firstIndex(of: step) else { return .pending }
        let current = coordinator.currentStep
        if current == .completed {
            return .done
        }
        if current == .failed {
            // After failure, mark steps before the failure as done; the rest pending.
            // Since we don't have a "last successful step" pointer, treat all pending —
            // the error row carries the explanation.
            return .pending
        }
        guard let currentIdx = order.firstIndex(of: current) else { return .pending }
        if stepIdx < currentIdx {
            return .done
        }
        if stepIdx == currentIdx {
            return .active
        }
        return .pending
    }

    // MARK: - Section progress

    private var sectionProgress: some View {
        let total = coordinator.sections.count
        let idx = min(coordinator.currentSectionIdx, max(total - 1, 0))
        let title = coordinator.sections.indices.contains(idx)
            ? coordinator.sections[idx].title
            : ""
        return HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Section \(idx + 1) of \(total): \(title)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 18)
    }

    // MARK: - Error row

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
