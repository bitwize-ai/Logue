import SwiftUI

/// Shown while a store is still reading from disk, in place of an empty state.
///
/// An empty state during loading is a lie: "No Documents" with a button to make one, when the
/// documents exist and are seconds from appearing. It is also the worst possible moment to
/// offer that button — a document created then lands in a library that is about to be replaced.
///
/// Nothing is drawn for the first fraction of a second. A load that finishes quickly should look
/// instant, not like a spinner that flashed; a spinner appearing and vanishing inside 100ms reads
/// as a glitch and tells the user less than a blank pane does.
struct ContentLoadingView: View {
    var label: String = "Loading…"

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 10) {
            if isVisible {
                ProgressView()
                    .controlSize(.small)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: AppConstants.Delays.loadingIndicatorAppearance)
            withAnimation(.easeIn(duration: 0.15)) { isVisible = true }
        }
        .accessibilityLabel(label)
    }
}
