import SwiftUI

/// Phase A0: a streamlined 3-card welcome tour. Replaces the 11-page legacy
/// flow when no license/auth gates are required (today it's used as a
/// "welcome tour" the user can re-trigger from Settings; the legacy
/// `OnboardingView` still owns the first-launch licensing path).
///
/// Cards (in order):
///   1. Privacy promise — "Everything stays on your Mac".
///   2. Choose your model — basic picker over installed/MLX models.
///   3. Set your hotkey — pre-fills ⌥Space + ⌘⌃I as defaults.
struct OnboardingV2View: View {
    @Environment(\.dismiss) private var dismiss

    enum Card: Int, CaseIterable {
        case privacy
        case model
        case hotkey
    }

    @State private var current: Card = .privacy
    @State private var modelManager = ModelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(Card.allCases, id: \.self) { card in
                    if card == current {
                        cardView(card)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.spring, value: current)

            Divider()
            footer
        }
        .frame(width: 540, height: 460)
        .background(.regularMaterial)
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        switch card {
        case .privacy: privacyCard
        case .model: modelCard
        case .hotkey: hotkeyCard
        }
    }

    private var privacyCard: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
            Text("Everything stays on your Mac")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Logue runs every model, embedding, and inference call on-device. No data leaves this Mac. No analytics, no telemetry, no servers.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .padding(28)
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Choose your model", systemImage: "cpu")
                .font(.title2.weight(.semibold))
            Text("This model runs locally for chat, summaries, and on-device search. You can change it anytime in Settings → Models.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    let modelList = modelManager.allModels
                    if modelList.isEmpty {
                        Text("No models installed yet — open Settings → Models to browse.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(modelList, id: \.id) { model in
                            modelRow(model)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)

            Text("Tip: 4-bit quantized 7B models fit comfortably in 16 GB unified memory.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
    }

    private func modelRow(_ model: ModelConfiguration) -> some View {
        let isActive = modelManager.activeModelID == model.id
        return Button {
            modelManager.activeModelID = model.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName).font(.callout.weight(.medium))
                    Text(model.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hotkeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Set your hotkeys", systemImage: "command.square.fill")
                .font(.title2.weight(.semibold))
            Text("Logue exposes two cross-app shortcuts. Both are rebindable later from Settings → Shortcuts.")
                .font(.callout)
                .foregroundStyle(.secondary)

            shortcutCard(
                icon: "sparkles",
                title: "Menu-bar companion",
                combo: "⌥Space",
                detail: "Pop up a quick chat window from any app"
            )
            shortcutCard(
                icon: "text.cursor",
                title: "Inline writing assistant",
                combo: "⌘⌃I",
                detail: "Rewrite selected text in any app — Simplify, Expand, Fix Grammar, …"
            )

            Text("First time you use ⌘⌃I, macOS will ask for Accessibility permission so Logue can read your selection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(28)
    }

    private func shortcutCard(icon: String, title: String, combo: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(combo)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Card pager dots
            HStack(spacing: 6) {
                ForEach(Card.allCases, id: \.self) { card in
                    Circle()
                        .fill(card == current ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if current != .privacy {
                Button("Back") {
                    if let prev = Card(rawValue: current.rawValue - 1) {
                        current = prev
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Button(current == .hotkey ? "Get started" : "Continue") {
                if let next = Card(rawValue: current.rawValue + 1) {
                    current = next
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
