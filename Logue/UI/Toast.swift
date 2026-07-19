import SwiftUI

/// Lightweight, app-wide flash confirmation.
///
/// Use `ToastCenter.shared.show("Copied!")` from anywhere. The active toast
/// is rendered by the `.toastOverlay()` modifier attached to the app's root
/// window. Toasts auto-dismiss after `Toast.defaultDuration` and stack
/// vertically when fired in quick succession.
///
/// This is the consumer-grade replacement for "silent click and hope".
struct Toast: Identifiable, Equatable {
    /// 1.5 s — long enough to read, short enough to feel snappy.
    static let defaultDuration: Double = 1.5

    enum Kind: Equatable {
        case info
        case success
        case warning

        var icon: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: .accentColor
            case .success: .green
            case .warning: .orange
            }
        }
    }

    let id = UUID()
    let message: String
    let kind: Kind
    let duration: Double
}

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var active: [Toast] = []

    private init() {}

    /// Convenience for the most common case — a one-line success flash.
    func show(_ message: String, kind: Toast.Kind = .success, duration: Double = Toast.defaultDuration) {
        let toast = Toast(message: message, kind: kind, duration: duration)
        active.append(toast)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            await MainActor.run {
                self.active.removeAll { $0.id == toast.id }
            }
        }
    }
}

// MARK: - Renderer

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind.icon)
                .foregroundStyle(toast.kind.tint)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

private struct ToastOverlay: ViewModifier {
    @State private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            VStack(spacing: 8) {
                ForEach(center.active) { toast in
                    ToastView(toast: toast)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }
            }
            .padding(.top, 24)
            .animation(Motion.snappy, value: center.active)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Attach to the app's root view to render any toasts fired via
    /// `ToastCenter.shared.show(...)`.
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
