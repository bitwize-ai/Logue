import os.log
import SwiftUI

/// A paged showcase of features, used for two jobs that differ only in what they list:
/// the first-run tour of what Logue does, and the notes for releases the user has not
/// seen yet.
///
/// One card at a time with dots and a footer, matching `OnboardingView` — a fresh install
/// meets this immediately after that wizard, and a second, unfamiliar shape would read as
/// a different app.
struct WhatsNewView: View {
    enum Mode: Equatable {
        /// Fresh install: the headline features, whatever release brought them.
        case discover
        /// Releases the user has not seen, newest first.
        case whatsNew([WhatsNewRelease])

        /// What "What's New" opens when the user asks for it by name, from the Help menu
        /// or Settings: the notes for the release this build is. Falls back to the tour
        /// when this build predates every catalogued release.
        static var latestNotes: Mode {
            guard let latest = WhatsNewCatalog.latestRelease(notNewerThan: AppVersion.current) else {
                return .discover
            }
            return .whatsNew([latest])
        }

        /// The newest release this mode actually put in front of the user.
        ///
        /// Stamping the running version instead would be wrong for the two entry points
        /// that show a single release: opening Help → What's New on a build that is
        /// several releases ahead would mark the ones in between as seen without ever
        /// having shown them, and the stamp only ever rises.
        var seenThrough: AppVersion? {
            switch self {
            case .discover: AppVersion.current
            case let .whatsNew(releases): releases.map(\.version).max()
            }
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
        // Escape belongs to the sheet, not to the dismiss button — that button is hidden
        // on the last card, which otherwise left the deck with no keyboard way out.
        .onExitCommand { dismiss() }
        .onAppear {
            // Nothing to say, nothing to show.
            if pages.isEmpty {
                dismiss()
            }
        }
        // Recorded on the way out rather than on the way in: a crash in between should
        // cost a second showing, not swallow the notes permanently. `seenThrough` is what
        // was actually displayed, which is not always the running version.
        .onDisappear { WhatsNewGate.markSeen(upTo: mode.seenThrough) }
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

    @ViewBuilder
    private func visual(for feature: WhatsNewFeature) -> some View {
        let urls = WhatsNewCatalog.screenshotURLs(for: feature)
        if urls.isEmpty {
            Image(systemName: feature.symbol)
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
        } else {
            ShowcaseSequence(urls: urls, label: feature.title)
        }
    }

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

            // Both modes: gating this on the tour left the release notes with no way out
            // but clicking through every card.
            if !isLastPage {
                Button(dismissTitle) { dismiss() }
                    .buttonStyle(.borderless)
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
    /// A sequence loops rather than stopping on the last frame, because a user who arrives
    /// mid-cycle would otherwise see the steps out of order and never see the beginning.
    ///
    /// Images are decoded into this view's own state rather than a shared cache, so they
    /// are released when the sheet closes — a permanent cache of decoded screenshots costs
    /// tens of megabytes for a sheet opened about once per release.
    private struct ShowcaseSequence: View {
        let urls: [URL]
        let label: String

        @State private var images: [NSImage] = []
        @State private var step = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let logger = Logger(subsystem: AppConstants.bundleID, category: "WhatsNew")
        private static let crossfade: TimeInterval = 0.35

        var body: some View {
            VStack(spacing: 8) {
                if let image = images.indices.contains(step) ? images[step] : images.first {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        // A fixed well rather than a maximum: steps of a sequence are
                        // rarely the same shape, and sizing to each one in turn makes the
                        // title and caption jump every time the image changes.
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(radius: AppThemeConstants.shadowRadiusHover, y: 2)
                        .id(step)
                        .transition(.opacity)
                } else {
                    // Holds the well open while the art decodes, so the card does not
                    // reflow the moment it appears.
                    Color.clear.frame(height: 250)
                }

                // Without this a change of image reads as a glitch rather than as step 2 of 3.
                if images.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(images.indices, id: \.self) { position in
                            Capsule()
                                .fill(position == step ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: position == step ? 14 : 5, height: 5)
                        }
                    }
                    .animation(reduceMotion ? nil : Motion.spring, value: step)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text(label))
            // Keyed on the URLs so moving to a card with different art restarts the
            // sequence, and leaving the sheet cancels it. `reduceMotion` is part of the key
            // because the loop below reads it: toggling it mid-sequence must take effect.
            .task(id: TaskKey(urls: urls, reduceMotion: reduceMotion)) {
                images = urls.compactMap { url in
                    guard let image = NSImage(contentsOf: url) else {
                        // A packaging problem, not a user-facing one — the card still reads.
                        Self.logger.error("Unreadable What's New art: \(url.lastPathComponent, privacy: .public)")
                        return nil
                    }
                    return image
                }
                step = 0

                guard images.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: AppConstants.Delays.whatsNewSequenceStep)
                    guard !Task.isCancelled else { return }
                    let next = (step + 1) % images.count
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.crossfade)) {
                        step = next
                    }
                }
            }
        }

        /// Restarts the sequence when either the art or the motion preference changes.
        private struct TaskKey: Equatable {
            let urls: [URL]
            let reduceMotion: Bool
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
