import Foundation
@testable import Logue
import Testing

@Suite("Transcription gate")
struct TranscriptionGateTests {
    @Test("The gate starts closed")
    func startsClosed() {
        let gate = TranscriptionGate(tail: 0.4)
        #expect(gate.isOpen == false)
        #expect(gate.state == .closed)
    }

    @Test("Speech opens the gate")
    func speechOpensTheGate() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.speechStarted()
        #expect(gate.isOpen)
    }

    @Test("The gate stays open through the tail after speech ends")
    func tailKeepsTheGateOpen() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.speechStarted()
        gate.speechEnded(at: 10.0)
        gate.advance(to: 10.2)
        #expect(gate.isOpen, "the last word must not be cut off mid-syllable")
    }

    @Test("The gate closes once the tail has elapsed")
    func gateClosesAfterTheTail() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.speechStarted()
        gate.speechEnded(at: 10.0)
        gate.advance(to: 10.5)
        #expect(gate.isOpen == false)
        #expect(gate.state == .closed)
    }

    @Test("Speech resuming during the tail cancels the close")
    func speechDuringTailReopens() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.speechStarted()
        gate.speechEnded(at: 10.0)
        gate.advance(to: 10.2)
        gate.speechStarted()
        gate.advance(to: 11.0)
        #expect(gate.isOpen, "a pause between two words is not the end of the sentence")
        #expect(gate.state == .open)
    }

    @Test("Advancing time while closed does nothing")
    func advancingWhileClosedIsInert() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.advance(to: 500)
        #expect(gate.isOpen == false)
    }

    @Test("Speech ending without having started is ignored")
    func endWithoutStartIsIgnored() {
        var gate = TranscriptionGate(tail: 0.4)
        gate.speechEnded(at: 10)
        #expect(gate.state == .closed, "a stray end event must not open the gate by putting it in the tail")
    }
}
