import SwiftUI

/// Animated shimmer placeholder used while content is loading.
/// Linear-gradient moving across a neutral background simulates the
/// "light sweeping over paper" effect common in modern macOS/iOS apps.
///
/// Prefer over bare `ProgressView` when the shape of the eventual content
/// is known — a skeleton row shows users *where* content will appear, not
/// just *that* something is loading.
struct SkeletonView: View {
    var cornerRadius: CGFloat = AppThemeConstants.radiusSmall
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppThemeConstants.surfaceBackground)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.primary.opacity(0.08),
                            .clear,
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: phase * width)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.6
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

/// A single skeleton row matching the density of `CommandRow` / `MeetingListRowView` —
/// small circular avatar + two stacked text bars.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView(cornerRadius: 12)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonView()
                    .frame(height: 12)
                    .frame(maxWidth: 220, alignment: .leading)
                SkeletonView()
                    .frame(height: 10)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
