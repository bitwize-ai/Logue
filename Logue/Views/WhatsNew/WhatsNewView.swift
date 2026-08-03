// `os` rather than `os.log`: it carries both `Logger` and the `OSAllocatedUnfairLock`
// guarding the image cache.
import os
import SwiftUI

/// A paged showcase of features, used for two jobs that differ only in what they list:
/// the first-run tour of what Logue does, and the notes for releases the user has not
/// seen yet.
///
/// Structured like `OnboardingV2View` — one card at a time, dots and a footer — because
/// a user meets this right after that flow and a second, unfamiliar shape would read as
/// a different app.
struct WhatsNewView: View {
    enum Mode: Equatable {
        /// Fresh install: the headline features, whatever release brought them.
        case discover
        /// Releases the user has not seen, newest first.
        case whatsNew([WhatsNewRelease])

        /// What "What's New" opens when the user asks for it by name, from the Help menu
        /// or Settings: the notes for the release this build is. Falls back to the tour
        /// only if no release is catalogued, which would mean the catalog is empty.
        static var latestNotes: Mode {
            guard let latest = WhatsNewCatalog.latestRelease(notNewerThan: AppVersion.current) else {
                return .discover
            }
            return .whatsNew([latest])
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "WhatsNew")

    // MARK: - Pages

    /// A feature plus the release it belongs to, when that is worth naming.
    private struct Page: Identifiable {
        let id: String
        let feature: WhatsNewFeature
        /// Shown only when the user is catching up across more than one release, so
        /// they can tell which version brought what.
        let versionBadge: String?
    }

    private var pages: [Page] {
        switch mode {
        case .discover:
            return WhatsNewCatalog.tour.map {
                Page(id: $0.id, feature: $0, versionBadge: nil)
            }
        case let .whatsNew(releases):
            let spansReleases = releases.count > 1
            return releases.flatMap { release in
                release.features.map {
                    Page(
                        id: "\(release.version)-\($0.id)",
                        feature: $0,
                        versionBadge: spansReleases
                            ? UICopy.WhatsNew.versionBadge(release.version.description)
                            : nil
                    )
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .discover: UICopy.WhatsNew.discoverTitle
        case .whatsNew: UICopy.WhatsNew.updatedTitle
        }
    }

    /// Named in the header when there is exactly one release to report — repeating it
    /// on every card would be noise.
    private var headerVersion: String? {
        guard case let .whatsNew(releases) = mode, releases.count == 1 else { return nil }
        return releases.first.map { "Version \($0.version)" }
    }

    private var isLastPage: Bool {
        index >= pages.count - 1
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                ForEach(Array(pages.enumerated()), id: \.element.id) { position, page in
                    if position == index {
                        card(page)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.spring, value: index)

            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .background(.regularMaterial)
        // An empty catalog would leave a blank sheet with no way to read it as anything
        // other than a bug. Nothing to say means nothing to show.
        .onAppear {
            if pages.isEmpty {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if let headerVersion {
                Text(headerVersion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(min(index + 1, max(pages.count, 1))) of \(max(pages.count, 1))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Card

    private func card(_ page: Page) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            if let badge = page.versionBadge {
                Text(badge)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .foregroundStyle(Color.accentColor)
            }

            visual(for: page.feature)

            Text(page.feature.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(page.feature.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
    }

    /// The feature's art when it has any, the symbol when it does not. A feature without
    /// art is the ordinary case, not a degraded one.
    @ViewBuilder
    private func visual(for feature: WhatsNewFeature) -> some View {
        let images = screenshots(for: feature)
        if images.isEmpty {
            Image(systemName: feature.symbol)
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
        } else {
            ShowcaseSequence(images: images, label: feature.title)
        }
    }

    /// Loads a card's art once per card rather than on every body evaluation — a
    /// sequence re-renders on every step, and re-reading the PNGs each time would put a
    /// disk read on an animation frame.
    private func screenshots(for feature: WhatsNewFeature) -> [NSImage] {
        WhatsNewCatalog.screenshotURLs(for: feature).compactMap { url in
            guard let image = Self.imageCache.withLock({ $0[url] }) else {
                guard let loaded = NSImage(contentsOf: url) else {
                    // A packaging problem, not a user-facing one — the card still reads.
                    Self.logger.debug("Unreadable What's New screenshot for \(feature.id, privacy: .public)")
                    return nil
                }
                Self.imageCache.withLock { $0[url] = loaded }
                return loaded
            }
            return image
        }
    }

    /// Decoded art, keyed by URL. The sheet is short-lived and the catalog is small, so
    /// this is bounded by the number of screenshots that ship.
    ///
    /// `OSAllocatedUnfairLock` provides the thread-safety: the view is main-actor bound
    /// but `static` storage is not, so the lock is what makes the shared access safe.
    private static let imageCache = OSAllocatedUnfairLock<[URL: NSImage]>(initialState: [:])

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { position, _ in
                    Circle()
                        .fill(position == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            // Both modes, not just the tour. Gating this on `.discover` left the release
            // notes with no way out but clicking through every card: no button, and no
            // `.cancelAction` anywhere in the sheet, so Escape did nothing either.
            if !isLastPage {
                Button(dismissTitle) { dismiss() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }

            if index > 0 {
                Button(UICopy.WhatsNew.back) { index -= 1 }
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }

            Button(continueTitle) {
                if isLastPage {
                    dismiss()
                } else {
                    index += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// A card's art: a still when there is one image, a sequence when there are several.
    ///
    /// The sequence is the point — it lets a card show *where* a feature lives before
    /// showing what it does. It loops rather than stopping on the last frame, because a
    /// user who arrives mid-cycle would otherwise see the steps out of order and then
    /// never see the beginning.
    private struct ShowcaseSequence: View {
        let images: [NSImage]
        let label: String

        @State private var step = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(spacing: 8) {
                Image(nsImage: images[min(step, images.count - 1)])
                    .resizable()
                    .scaledToFit()
                    // A fixed well rather than a maximum: steps of a sequence are rarely
                    // the same shape, and sizing to each one in turn makes the title and
                    // caption jump every time the image changes.
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(radius: AppThemeConstants.shadowRadiusHover, y: 2)
                    .id(step)
                    .transition(.opacity)

                // Only when there is a sequence: without this a change of image reads as
                // a glitch rather than as step 2 of 3.
                if images.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(images.indices, id: \.self) { position in
                            Capsule()
                                .fill(position == step ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: position == step ? 14 : 5, height: 5)
                        }
                    }
                    .animation(Motion.spring, value: step)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text(label))
            // Keyed on the image set so switching cards restarts the sequence from its
            // first step, and leaving the card cancels it.
            .task(id: images.count) {
                step = 0
                guard images.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: AppConstants.Delays.whatsNewSequenceStep)
                    guard !Task.isCancelled else { return }
                    let next = (step + 1) % images.count
                    if reduceMotion {
                        step = next
                    } else {
                        withAnimation(.easeInOut(duration: 0.35)) { step = next }
                    }
                }
            }
        }
    }

    private var continueTitle: String {
        guard isLastPage else { return UICopy.WhatsNew.next }
        return mode == .discover ? UICopy.WhatsNew.finishTour : UICopy.WhatsNew.finishNotes
    }

    /// "Skip" reads as skipping an introduction; for notes already being read it is
    /// closing them.
    private var dismissTitle: String {
        mode == .discover ? UICopy.WhatsNew.skip : UICopy.WhatsNew.close
    }
}
