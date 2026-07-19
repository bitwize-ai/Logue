import SwiftUI

/// Tiny horizontal spinner + label for inline busy states — model activation,
/// connection testing, short background checks. Standardizes the spacing, sizing,
/// and foreground style so loading UI feels consistent across the app.
///
/// Use contextual text ("Activating…", "Testing…") rather than a bare "Loading" —
/// the audit flagged the generic text as a polish gap.
struct InlineProgressLabel: View {
    let text: String
    var scale: CGFloat = 0.6

    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(scale)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
