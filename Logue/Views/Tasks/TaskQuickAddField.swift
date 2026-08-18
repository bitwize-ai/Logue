import SwiftUI

/// The capture box at the top of the Tasks list.
///
/// Shows a live reading of what the parser understood, so the syntax teaches itself rather
/// than living in a help page nobody opens.
struct TaskQuickAddField: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    let onCapture: (String) -> Void
    /// Bumped by the toolbar's + button to put the cursor here.
    ///
    /// A counter rather than a boolean: a flag reset asynchronously races with a second
    /// press, and the second press is exactly when a user is checking whether the button
    /// did anything.
    var focusRequest: Int = 0

    private var preview: ParsedTask? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return TaskTextParser.parse(trimmed)
    }

    /// Only worth showing when the parser found something the plain text does not already say.
    private var hasPreview: Bool {
        guard let preview else { return false }
        return preview.dueDate != nil || !preview.tags.isEmpty
            || preview.priority != .medium || preview.recurrence != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)

                TextField("Send the deck tomorrow #launch !", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 6)
                    .focused($isFocused)
                    .onSubmit(capture)
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let preview, hasPreview {
                previewChips(preview)
            }
        }
        .onChange(of: focusRequest) {
            isFocused = true
        }
    }

    private func previewChips(_ parsed: ParsedTask) -> some View {
        HStack(spacing: 6) {
            if let due = parsed.dueDate {
                chip(due.formatted(date: .abbreviated, time: .omitted), symbol: "calendar")
            }
            if parsed.priority != .medium {
                chip(parsed.priority.displayName, symbol: parsed.priority.symbolName)
            }
            if let recurrence = parsed.recurrence {
                chip(recurrence.displayName, symbol: "repeat")
            }
            ForEach(parsed.tags, id: \.self) { tag in
                chip(tag, symbol: "number")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func chip(_ label: String, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func capture() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCapture(trimmed)
        text = ""
    }
}
