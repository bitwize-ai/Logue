import SwiftUI

/// Chat-home welcome hero — title, subtitle, prompt chips, recent
/// conversations, daily tip. Used as the resting state of `AgentChatView`
/// when no conversation is open.
///
/// Distinct from `Views/Components/EmptyStateView.swift` which is the
/// generic icon+title+CTA placeholder used elsewhere.
///
/// Layout:
///
/// ```
///       (icon)
///   Title text here
///   Subtitle / tagline
///
///   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
///   │chip │ │chip │ │chip │ │chip │
///   └─────┘ └─────┘ └─────┘ └─────┘
///
///   ─── Recent ───
///   • last conversation 1
///   • last conversation 2
///
///   💡 Daily tip text
/// ```
struct ChatHomeEmptyState: View {
    struct Chip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let prompt: String
    }

    struct RecentItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let action: () -> Void
    }

    let icon: String
    let title: String
    let subtitle: String
    let chips: [Chip]
    var recents: [RecentItem] = []
    var dailyTip: String?
    var onChipTap: (Chip) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !chips.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    ForEach(chips) { chip in
                        chipButton(chip)
                    }
                }
                .frame(maxWidth: 520)
            }

            if !recents.isEmpty {
                recentSection
            }

            if let tip = dailyTip, !tip.isEmpty {
                tipRow(tip)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chipButton(_ chip: Chip) -> some View {
        Button {
            onChipTap(chip)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: chip.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chip.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(chip.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: 520)

            VStack(spacing: 4) {
                ForEach(recents) { item in
                    Button(action: item.action) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let sub = item.subtitle {
                                    Text(sub)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)
        }
    }

    private func tipRow(_ tip: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.system(size: 10))
            Text(tip)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.secondary.opacity(0.08))
        )
    }
}
