import Foundation
import os

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

        guard let dict = dictionary(fromJSON: trimmed) else {
            // Not JSON we can read. Show it anyway — it is still what the tool was called
            // with — but bounded, which is the whole point of this type.
            return DisplayText.clamp(DisplayText.singleLine(trimmed), to: maxTotalLength)
        }

        // The key is the model's text as much as the value is, so it gets the same scrub.
        let pairs = dict.keys.sorted().map { key in
            let value = DisplayText.singleLine(String(describing: dict[key] ?? ""))
            return "\(DisplayText.singleLine(key)): \(DisplayText.clamp(value, to: maxValueLength))"
        }
        return DisplayText.clamp(pairs.joined(separator: ", "), to: maxTotalLength)
    }

    /// A tool call's arguments as a dictionary, or `nil` when they are not a JSON object.
    ///
    /// Shared with `ToolApprovalPrompt`, which reads single arguments out of the same string.
    /// Logged at debug level only: this runs while a card is being drawn, so a malformed call
    /// would otherwise write a line per render.
    static func dictionary(fromJSON json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            // The length, not the text: arguments carry document bodies and web addresses.
            logger.debug(
                "Tool arguments are not JSON (\(json.count) characters): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "ToolArgumentSummary")
}
