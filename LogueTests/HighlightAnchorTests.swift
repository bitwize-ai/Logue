import Foundation
@testable import Logue
import Testing

@Suite("Highlight anchoring")
struct HighlightAnchorTests {
    private func segment(_ text: String, _ start: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 8)
    }

    private func highlight(_ label: String, at timestamp: TimeInterval) -> Bookmark {
        Bookmark(label: label, timestamp: timestamp, color: .blue, source: .ai)
    }

    @Test("A highlight moves to the moment its words were spoken")
    func anchorsToMatchingSegment() {
        let segments = [
            segment("Here you bring your rough cut and notes", 0),
            segment("In the last twenty years we have seen an explosion in data", 41),
            segment("Some of it is just machine data and noise", 62),
        ]
        // The model guessed 3s for something said at 41s — the clustering seen in real meetings.
        let anchored = HighlightAnchor.anchored(
            [highlight("Data Explosion in Last 20 Years", at: 3)],
            to: segments
        )
        #expect(anchored[0].timestamp == 41)
    }

    @Test("A highlight that matches nothing keeps the estimate it came with")
    func unmatchedKeepsItsTimestamp() {
        let segments = [segment("entirely unrelated conversation", 0)]
        let anchored = HighlightAnchor.anchored(
            [highlight("Quarterly Revenue Forecast", at: 30)],
            to: segments
        )
        #expect(anchored[0].timestamp == 30)
    }

    @Test("One word in common is not a match")
    func singleWordIsNotEnough() {
        let segments = [segment("the data was fine", 0), segment("nothing relevant here", 50)]
        let anchored = HighlightAnchor.anchored(
            [highlight("Data Explosion Twenty Years", at: 12)],
            to: segments
        )
        #expect(anchored[0].timestamp == 12, "coincidence must not move a highlight")
    }

    @Test("Identity and labelling survive anchoring")
    func preservesEverythingElse() {
        let segments = [segment("machine data and noise in the pipeline", 20)]
        let original = highlight("Machine Data and Noise", at: 2)
        let anchored = HighlightAnchor.anchored([original], to: segments)[0]

        #expect(anchored.id == original.id)
        #expect(anchored.label == original.label)
        #expect(anchored.color == original.color)
        #expect(anchored.source == .ai)
        #expect(anchored.timestamp == 20)
    }

    @Test("With no transcript there is nothing to anchor to")
    func emptyTranscriptIsLeftAlone() {
        let original = highlight("Anything", at: 9)
        #expect(HighlightAnchor.anchored([original], to: [])[0].timestamp == 9)
    }
}
