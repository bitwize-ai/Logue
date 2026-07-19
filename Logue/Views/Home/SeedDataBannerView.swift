import SwiftUI

/// Dismissible banner shown on the Overview when sample data is still present.
struct SeedDataBannerView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.hasClearedSeedData) private var hasClearedSeedData = false
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore

    @State private var showConfirmation = false
    @State private var isDismissed = false

    /// Only show the banner when seed data was actually loaded (not real user data from disk).
    private var storesLoadedSeedData: Bool {
        meetingStore.loadedSeedData || documentStore.loadedSeedData
    }

    var body: some View {
        if !hasClearedSeedData, !isDismissed, storesLoadedSeedData {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.brandPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Exploring with sample data")
                        .font(.subheadline.weight(.medium))
                    Text("Clear examples when you're ready to start fresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear Examples") {
                    showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppThemeConstants.accent)
                .accessibilityLabel("Clear example data")
                .accessibilityHint("Removes all sample documents, meetings, and folders")

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss sample data banner")
            }
            .padding(14)
            .background(
                AppThemeConstants.brandPrimary.opacity(AppThemeConstants.hoverOpacity),
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .strokeBorder(AppThemeConstants.brandPrimary.opacity(AppThemeConstants.opacityMedium), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .confirmationDialog(
                "Clear all example data?",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Examples", role: .destructive) {
                    clearSeedData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all sample documents, meetings, and folders. This cannot be undone.")
            }
        }
    }

    private func clearSeedData() {
        withAnimation(.easeOut(duration: 0.25)) {
            documentStore.clearAllData()
            meetingStore.clearAllData()
            spaceStore.clearAllData()
            hasClearedSeedData = true
        }
    }
}
