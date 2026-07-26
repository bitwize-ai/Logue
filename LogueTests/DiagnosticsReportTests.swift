import Foundation
@testable import Logue
import Testing

/// The diagnostics block is pasted into public GitHub issues, so the important
/// assertions are about what must never appear in it.
@Suite("DiagnosticsReport")
@MainActor
struct DiagnosticsReportTests {
    @Test("Report includes app version, macOS version, and device model")
    func includesEnvironmentBasics() {
        let text = DiagnosticsReport.generate()
        #expect(text.contains(BugReportInfo.appVersion))
        #expect(text.contains(BugReportInfo.macOSVersion))
        #expect(text.contains(BugReportInfo.deviceModel))
    }

    @Test("Report never contains the user's home directory path")
    func excludesHomeDirectory() {
        let text = DiagnosticsReport.generate()
        #expect(text.contains(NSHomeDirectory()) == false)
        #expect(text.contains("/Users/") == false)
    }

    @Test("Report never contains the account user name")
    func excludesUserName() {
        let text = DiagnosticsReport.generate()
        let userName = NSUserName()
        if !userName.isEmpty {
            #expect(text.localizedCaseInsensitiveContains(userName) == false)
        }
    }

    @Test("Report never contains a full URL")
    func excludesURLs() {
        let text = DiagnosticsReport.generate()
        #expect(text.contains("http://") == false)
        #expect(text.contains("https://") == false)
    }

    @Test("Report reports external-provider configuration as a flag, not a key")
    func reportsProviderFlagOnly() {
        let text = DiagnosticsReport.generate()
        // Key-shaped prefixes must never appear.
        #expect(text.contains("sk-") == false)
        #expect(text.lowercased().contains("api key") == false)
        #expect(text.contains("External providers:"))
    }

    @Test("Sanitising strips control characters and clamps length")
    func sanitiseStripsControlCharacters() {
        let dirty = "model\u{0}name\nwith\tcontrol"
        let clean = DiagnosticsReport.sanitise(dirty)
        #expect(clean.contains("\u{0}") == false)
        #expect(clean.contains("\n") == false)
        #expect(clean.contains("\t") == false)
    }

    @Test("Sanitising truncates over-long values")
    func sanitiseTruncates() {
        let clean = DiagnosticsReport.sanitise(String(repeating: "a", count: 500))
        #expect(clean.count <= DiagnosticsReport.maxValueLength)
    }

    @Test("Sanitising replaces an empty value with a placeholder")
    func sanitiseHandlesEmpty() {
        #expect(DiagnosticsReport.sanitise("") == "unknown")
        #expect(DiagnosticsReport.sanitise("   ") == "unknown")
    }

    @Test("Report is plain multi-line text suitable for pasting")
    func reportIsMultiLine() {
        let lines = DiagnosticsReport.generate().components(separatedBy: "\n")
        #expect(lines.count >= 4)
    }
}
