import Foundation

// MARK: - BlockFrameStore

/// Holds each block's on-screen frame so a cross-block drag can hit-test which block the
/// pointer is over.
///
/// Deliberately a plain reference type rather than `@State` storage or `@Observable`.
/// Every block reports its frame in the scroll coordinate space, so *all* of those frames
/// change on every frame of a scroll. Keeping them in observed view state meant each scrolled
/// frame invalidated the whole editor body, which rebuilt every block row and ran
/// `updateNSView` on every block's text view — measured at ~48 body evaluations and ~2,200
/// text-view updates per second on a 45-block document, which is what made scrolling stutter.
/// Nothing renders from these frames, so writing them must not invalidate anything.
///
/// Thread-safety: every access goes through `lock`. The frames are written from SwiftUI's
/// preference callback and read from an `NSEvent` monitor; both run on the main thread today,
/// but the lock means that isn't load-bearing.
final class BlockFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [BlockID: CGRect] = [:]

    func replaceAll(with newFrames: [BlockID: CGRect]) {
        lock.lock()
        defer { lock.unlock() }
        frames = newFrames
    }

    /// Hit-tests which block sits at the given point.
    ///
    /// Vertical-only: blocks span the full content width, so the x coordinate carries no
    /// information.
    ///
    /// The bounds are inclusive at both ends, so any two frames that touch or overlap both
    /// contain the point on their shared edge. The editor's current layout does not produce
    /// that case — its `VStack` spacing leaves a measured 4pt gap between consecutive row
    /// frames, and a point inside a gap matches nothing — but the store cannot assume a
    /// caller's frames are disjoint, and dropping that spacing to zero would create a tie at
    /// every boundary. Resolving to the topmost match keeps the answer stable either way;
    /// picking whichever key dictionary iteration happened to yield first would not.
    func blockID(at point: CGPoint) -> BlockID? {
        lock.lock()
        defer { lock.unlock() }
        // `lazy` so the filter doesn't build an intermediate dictionary on every hit test.
        return frames.lazy
            .filter { point.y >= $0.value.minY && point.y <= $0.value.maxY }
            .min { $0.value.minY < $1.value.minY }?
            .key
    }
}
