import Foundation
import Testing

@testable import Logue

/// Covers `BlockFrameStore` in isolation: frames go in, a block comes out.
///
/// Every case here supplies coordinates in one consistent space, so a passing suite says
/// nothing about whether cross-block drag selection works in the app. It cannot: the drag
/// path feeds this store a point in the window's `contentView` coordinates while the frames
/// are captured in the `editorScroll` space, and those two disagree on both origin and y
/// direction. That mismatch is tracked separately — don't read these tests as coverage of
/// the drag feature.
@Suite("Block frame hit-testing")
struct BlockFrameStoreTests {
    /// Three stacked blocks, 100pt tall each, matching how the editor lays rows out.
    private func stackedStore() -> (BlockFrameStore, [BlockID]) {
        let ids = [UUID(), UUID(), UUID()]
        let store = BlockFrameStore()
        store.replaceAll(with: [
            ids[0]: CGRect(x: 0, y: 0, width: 600, height: 100),
            ids[1]: CGRect(x: 0, y: 100, width: 600, height: 100),
            ids[2]: CGRect(x: 0, y: 200, width: 600, height: 100),
        ])
        return (store, ids)
    }

    @Test("Finds the block containing the point")
    func findsContainingBlock() {
        let (store, ids) = stackedStore()
        #expect(store.blockID(at: CGPoint(x: 30, y: 50)) == ids[0])
        #expect(store.blockID(at: CGPoint(x: 30, y: 150)) == ids[1])
        #expect(store.blockID(at: CGPoint(x: 30, y: 250)) == ids[2])
    }

    @Test("Ignores the x coordinate, since blocks span the full width")
    func ignoresHorizontalPosition() {
        let (store, ids) = stackedStore()
        #expect(store.blockID(at: CGPoint(x: -500, y: 150)) == ids[1])
        #expect(store.blockID(at: CGPoint(x: 99999, y: 150)) == ids[1])
    }

    @Test("Returns nil above and below the content")
    func missesOutsideContent() {
        let (store, _) = stackedStore()
        #expect(store.blockID(at: CGPoint(x: 30, y: -1)) == nil)
        #expect(store.blockID(at: CGPoint(x: 30, y: 301)) == nil)
    }

    @Test("An empty store hit-tests to nothing rather than trapping")
    func emptyStoreMisses() {
        #expect(BlockFrameStore().blockID(at: .zero) == nil)
    }

    @Test("A point between two blocks matches neither")
    func gapBetweenBlocksMisses() {
        // The editor's VStack spacing leaves a measured 4pt gap between consecutive row
        // frames, so there is a thin band between blocks that belongs to no block.
        let upper = UUID()
        let lower = UUID()
        let store = BlockFrameStore()
        store.replaceAll(with: [
            upper: CGRect(x: 0, y: 0, width: 600, height: 100),
            lower: CGRect(x: 0, y: 104, width: 600, height: 100),
        ])
        #expect(store.blockID(at: CGPoint(x: 30, y: 100)) == upper)
        #expect(store.blockID(at: CGPoint(x: 30, y: 102)) == nil)
        #expect(store.blockID(at: CGPoint(x: 30, y: 104)) == lower)
    }

    @Test("Two frames sharing an edge resolve to the upper one")
    func sharedEdgeResolvesUpward() {
        // Not reachable through the editor's current spacing, but the bounds are inclusive,
        // so this is what a zero-spacing layout would hit — and it must not be arbitrary.
        let upper = UUID()
        let lower = UUID()
        let store = BlockFrameStore()
        store.replaceAll(with: [
            upper: CGRect(x: 0, y: 0, width: 600, height: 100),
            lower: CGRect(x: 0, y: 100, width: 600, height: 100),
        ])
        for _ in 0 ..< 50 {
            #expect(store.blockID(at: CGPoint(x: 30, y: 100)) == upper)
        }
    }

    @Test("Overlapping frames resolve to the topmost block, not an arbitrary one")
    func overlapIsDeterministic() {
        // Dictionary iteration order is unstable, so an arbitrary pick would make a drag over
        // overlapping frames select different blocks on different runs.
        let upper = UUID()
        let lower = UUID()
        let store = BlockFrameStore()
        store.replaceAll(with: [
            upper: CGRect(x: 0, y: 0, width: 600, height: 100),
            lower: CGRect(x: 0, y: 50, width: 600, height: 100),
        ])
        for _ in 0 ..< 50 {
            #expect(store.blockID(at: CGPoint(x: 30, y: 75)) == upper)
        }
    }

    @Test("Replacing frames drops the previous layout entirely")
    func replaceAllDiscardsStaleFrames() {
        let (store, ids) = stackedStore()
        let replacement = UUID()
        store.replaceAll(with: [replacement: CGRect(x: 0, y: 0, width: 600, height: 100)])
        #expect(store.blockID(at: CGPoint(x: 30, y: 50)) == replacement)
        // Blocks from the old layout must not linger and win a later hit test.
        #expect(store.blockID(at: CGPoint(x: 30, y: 250)) == nil)
        #expect(!ids.contains(where: { $0 == store.blockID(at: CGPoint(x: 30, y: 50)) }))
    }
}
