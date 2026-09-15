import Foundation
@testable import Logue
import Testing

@Suite("Speech transcriber engine")
@MainActor
struct SpeechTranscriberEngineTests {
    @Test("Finish keeps leftover live text as a final segment")
    func finishFlushesVolatileText() async {
        let engine = SpeechTranscriberEngine()
        var received: [String] = []
        engine.onFinalSegment = { received.append($0.text) }
        engine.volatileText = "hello from the meeting"
        await engine.finish()
        #expect(received == ["hello from the meeting"])
        #expect(engine.volatileText.isEmpty)
    }

    @Test("Finish does not emit blank leftover text")
    func finishIgnoresBlankVolatileText() async {
        let engine = SpeechTranscriberEngine()
        var received: [String] = []
        engine.onFinalSegment = { received.append($0.text) }
        engine.volatileText = "   "
        await engine.finish()
        #expect(received.isEmpty)
    }
}
