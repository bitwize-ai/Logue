import Foundation

/// The one line a tool card shows for what a tool was called with.
///
/// Lifted out of `ToolExecutionCard.formatArguments`, which had two problems that only
/// became visible at island width.
///
/// **It was unordered.** It mapped over a `Dictionary`, and Swift dictionaries have no order
/// — so the same call rendered `query: standup, limit: 5` on one pass and `limit: 5, query:
/// standup` on the next. In a 700pt card with the line truncated, that means the argument you
/// can actually read changes as the view re-renders.
///
/// **It was unbounded.** `update_document` carries the whole new body as an argument, so the
/// string handed to `Text` was the length of a document. `lineLimit(1)` hid the tail but the
/// text was still laid out, and everything after it on that row — the status badge, the
/// Approve and Deny buttons — got pushed for room that was never going to be used.
///
/// Free of SwiftUI, so both the ordering and the bounds are testable.
enum ToolArgumentSummary {
    /// Longest a single value may be before it is cut.
    static let maxValueLength = 48
    /// Longest the whole line may be, however many arguments there are.
    static let maxTotalLength = 160

    /// What to show for `json`, or an empty string when there is nothing worth showing.
    ///
    /// Keys are sorted so the line is stable across renders. Alphabetical is arbitrary but it
    /// is *the same* arbitrary every time, which is the property that matters — the reader is
    /// looking at a line they may have to compare with the one above it.
    static func summary(fromJSON json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else { return "" }

        guard let data = trimmed.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Not JSON we can read. Show it anyway — it is still what the tool was called
            // with — but bounded, which is the whole point of this type.
            return clamp(flatten(trimmed), to: maxTotalLength)
        }

        let pairs = dict.keys.sorted().map { key in
            "\(key): \(clamp(flatten(String(describing: dict[key] ?? "")), to: maxValueLength))"
        }
        return clamp(pairs.joined(separator: ", "), to: maxTotalLength)
    }

    /// Puts a value on one line.
    ///
    /// A document body arrives with its newlines intact, and a `Text` limited to one line
    /// renders the first of them and hides the rest — so a multi-paragraph argument looked
    /// like a short one. Collapsing whitespace makes the truncation honest.
    private static func flatten(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cuts to `limit`, marking that something was cut.
    ///
    /// The ellipsis is inside the budget rather than added to it, so the result is never
    /// longer than the caller asked for.
    private static func clamp(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        guard limit > 1 else { return String(value.prefix(limit)) }
        return String(value.prefix(limit - 1)) + "…"
    }
}
