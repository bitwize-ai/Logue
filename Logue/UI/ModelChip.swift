import SwiftUI

/// Header chip showing the active model. Click to open the inline model
/// picker. Always sits next to the `TrustChip` so the user sees both
/// "what's running" and "where it's running" in one glance.
///
/// Uses `ModelManager.shared.activeModel` as source of truth.
struct ModelChip: View {
    var modelName: String
    var isLoading: Bool = false
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isLoading ? "circle.dotted" : "cpu")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Active model — click to change")
        .accessibilityLabel("Active model: \(displayName). Click to change.")
    }

    /// Trim namespacey model IDs ("mlx-community/Llama-3.2-3B-Instruct-4bit")
    /// to something user-friendly ("Llama 3.2 3B").
    private var displayName: String {
        let last = modelName.split(separator: "/").last.map(String.init) ?? modelName
        return last
            .replacingOccurrences(of: "-Instruct", with: "")
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-8bit", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

#Preview {
    VStack(spacing: 10) {
        ModelChip(modelName: "mlx-community/Llama-3.2-3B-Instruct-4bit") {}
        ModelChip(modelName: "Qwen-2.5", isLoading: true) {}
    }
    .padding()
}
