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
    /// information. Ties are impossible in practice because block frames don't overlap
    /// vertically, but a deterministic answer still beats an arbitrary one, so the topmost
    /// match wins.
    func blockID(at point: CGPoint) -> BlockID? {
        lock.lock()
        defer { lock.unlock() }
        return frames
            .filter { point.y >= $0.value.minY && point.y <= $0.value.maxY }
            .min { $0.value.minY < $1.value.minY }?
            .key
    }
}
