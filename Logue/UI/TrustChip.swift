import SwiftUI

/// Privacy-first trust signal. Two variants:
/// - `.compact` — a small chip for the chat header (next to the model name).
/// - `.banner` — a full-width line for under the input or in Settings.
///
/// Always says some variation of "your data stays on this Mac." This is
/// Logue's #1 brand cue and should appear wherever the user is making a
/// decision (typing a message, picking a model, opening Settings).
struct TrustChip: View {
    enum Variant {
        case compact
        case banner
    }

    let variant: Variant
    let label: String
    let detail: String?

    init(variant: Variant = .compact, label: String = "Local", detail: String? = nil) {
        self.variant = variant
        self.label = label
        self.detail = detail
    }

    var body: some View {
        switch variant {
        case .compact:
            compactChip
        case .banner:
            banner
        }
    }

    private var compactChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.green.opacity(0.18), lineWidth: 0.5)
        )
        .help(detail ?? "Everything happens on your Mac. No data leaves this device.")
        .accessibilityLabel("On-device — \(detail ?? "no data leaves this Mac")")
    }

    private var banner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11, weight: .medium))
            Text(detail ?? "Local model · Offline-capable · No data leaves this Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 12) {
        TrustChip(variant: .compact, label: "Local")
        TrustChip(variant: .banner)
    }
    .padding()
}
