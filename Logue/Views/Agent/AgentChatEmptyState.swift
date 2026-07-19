import SwiftUI

/// Compact welcome hero shown above the centered input bar in the empty-state
/// branch of `AgentChatView`. Vertical centering is handled by the parent VStack
/// (no `Spacer()`s here) so the hero + input bar render as a single unit, like
/// ChatGPT's pre-conversation layout.
///
/// `compact: false` preserves the legacy full-area layout for any caller that
/// still wants the bottom-pinned input + top-spanning empty state behavior.
struct AgentChatEmptyState: View {
    var compact: Bool = true

    var body: some View {
        if compact {
            compactHero
        } else {
            legacyFullArea
        }
    }

    // MARK: - Compact (new default)

    private var compactHero: some View {
        VStack(spacing: 16) {
            iconAndTitle
            privacyBadge
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 720)
    }

    // MARK: - Legacy (Spacer-driven)

    private var legacyFullArea: some View {
        VStack(spacing: 24) {
            Spacer()
            iconAndTitle
            Spacer()
            privacyBadge
                .padding(.bottom, 8)
        }
        .padding(32)
    }

    // MARK: - Pieces

    private var iconAndTitle: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(AppThemeConstants.brandPrimary.opacity(0.7))

            Text(UICopy.Empty.chatTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(UICopy.Empty.chatSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private var privacyBadge: some View {
        TrustChip(variant: .banner)
    }
}
