import Foundation
@testable import Logue
import Testing

@Suite("TextAnalysisRequest")
struct TextAnalysisRequestTests {
    @Test("Defaults initialize text correctly")
    func defaults() {
        let text = "Sample text for testing"
        let request = TextAnalysisRequest(text: text)

        #expect(request.text == text)
        // Default values
        #expect(request.cursorOffset == 0)
        #expect(request.goalMode == .casual)
    }

    @Test("Custom initialization sets goal mode and offset")
    func customInit() {
        let request = TextAnalysisRequest(text: "Test content", cursorOffset: 5, goalMode: .academic)
        #expect(request.cursorOffset == 5)
        #expect(request.goalMode == .academic)
    }
}
