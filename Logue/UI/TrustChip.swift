import SwiftUI

/// Privacy-first trust signal: a small chip for the chat header, next to the model name.
///
/// Always says some variation of "your data stays on this Mac." This is
/// Logue's #1 brand cue and should appear wherever the user is making a
/// decision (typing a message, picking a model, opening Settings).
///
/// There was a `.banner` variant for a full-width line under the input. Home's landing
/// replaced the hero that used it, and the window subtitle says the same thing from
/// `UICopy.Trust.bannerFull`, so it went with its last caller.
struct TrustChip: View {
    enum Variant {
        case compact
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
        compactChip
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
}

#Preview {
    TrustChip(variant: .compact, label: "Local")
        .padding()
}
