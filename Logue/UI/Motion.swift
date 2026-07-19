import SwiftUI

/// Centralized animation tokens. Every UI primitive in the app pulls its
/// animations from here so visual rhythm stays consistent.
///
/// Honors `accessibilityDisplayShouldReduceMotion` — when the user has
/// "Reduce motion" enabled in System Settings → Accessibility, springs
/// fall back to short cross-fades.
///
/// Usage:
///   ```swift
///   .animation(Motion.spring, value: someState)
///   .transition(Motion.bubbleIn)
///   ```
enum Motion {
    // MARK: - Spring tokens

    /// Default consumer-grade spring. Use for most state transitions
    /// (panels, popovers, toolbars, mode toggles).
    static var spring: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// Snappier spring. Use for small affordances (toast, pill, chip).
    static var snappy: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 0.88)
    }

    /// Slower, softer spring. Use for large slide-ins (Canvas, sidebar).
    static var soft: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.45, dampingFraction: 0.82)
    }

    /// Plain cross-fade. Use for content swaps where motion would distract.
    static var crossfade: Animation {
        .easeInOut(duration: reduceMotion ? 0.1 : 0.18)
    }

    // MARK: - Message bubble entry

    /// New assistant message: 4 pt slide up + fade in over 180 ms.
    static var bubbleAssistant: Animation {
        reduceMotion ? crossfade : .spring(response: 0.32, dampingFraction: 0.88)
    }

    /// New user message: 4 pt slide up + fade in over 120 ms (user-initiated, snappier).
    static var bubbleUser: Animation {
        reduceMotion ? crossfade : .spring(response: 0.22, dampingFraction: 0.9)
    }

    /// Reusable transition for incoming message bubbles.
    static var bubbleIn: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: - Streaming text

    /// Per-character fade-in window for streaming tokens. Keep small so
    /// the trailing caret stays visually attached to the latest text.
    static var charStream: Animation {
        reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.08)
    }

    // MARK: - Conversation history stagger

    /// Per-row delay when loading a conversation thread. Stops at 8 rows
    /// so cold-loading a long conversation doesn't feel sluggish.
    static func staggerDelay(forRow index: Int, max: Int = 8) -> Double {
        if reduceMotion {
            return 0
        }
        return Double(min(index, max)) * 0.03
    }

    // MARK: - Reduce-motion observer

    /// Cached check — re-read on every access since the system can flip it
    /// while the app is running. NSWorkspace publishes a notification but
    /// for animation tokens a per-call check is cheap enough.
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
