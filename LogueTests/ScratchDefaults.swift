import Foundation
import Testing

/// A `UserDefaults` suite that exists only for the duration of one test.
///
/// Three suites had grown their own near-verbatim copy of this. It is one helper because the
/// detail that matters is easy to get wrong in a way that passes: a `?? .standard` fallback
/// writes the app's real keys in the running user's preferences — wiping settings they were
/// actually using — and every assertion still succeeds, so nothing reports it. `#require` fails
/// the test instead, and the teardown removes the whole domain rather than the keys it can
/// remember to name.
///
/// - Parameter label: distinguishes suite names in a `defaults read`, for anything that leaks.
func withScratchDefaults(
    label: String = "logue-test",
    _ body: (UserDefaults) throws -> Void
) throws {
    let name = "\(label)-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}
