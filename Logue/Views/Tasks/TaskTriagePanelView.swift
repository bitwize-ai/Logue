import SwiftUI

/// Shows what triage proposed. Nothing here changes a task until the user presses Apply.
struct TaskTriagePanelView: View {
    @State private var service = TaskTriageService.shared
    @State private var store = TaskStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if service.isRunning {
                ProgressView("Reviewing your tasks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = service.lastError {
                message(error, symbol: "exclamationmark.triangle")
            } else if service.suggestions.isEmpty {
                message("Nothing to suggest — your list looks in order.", symbol: "checkmark.circle")
            } else {
                List(service.suggestions) { suggestion in
                    row(suggestion)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Triage")
                .font(.headline)
            if service.reviewedCount > 0 {
                Text(reviewedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// States the count explicitly, so a capped review never reads as a complete one.
    private var reviewedSummary: String {
        let plural = service.reviewedCount == 1 ? "" : "s"
        return "Reviewed \(service.reviewedCount) open task\(plural). "
            + "Nothing changes until you apply it."
    }

    @ViewBuilder
    private func row(_ suggestion: TriageSuggestion) -> some View {
        if let task = store.task(id: suggestion.taskID) {
            VStack(alignment: .leading, spacing: 6) {
                Label(suggestion.kind.displayName, systemImage: suggestion.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(task.title)
                    .font(.body.weight(.medium))

                Text(suggestion.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    // A duplicate carries no patch: deciding which of two tasks dies is the
                    // user's call, so there is nothing to one-click.
                    if suggestion.patch != nil {
                        Button("Apply") {
                            store.update(TaskTriage.applying(suggestion, to: task))
                            service.dismiss(suggestion)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Dismiss") { service.dismiss(suggestion) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
