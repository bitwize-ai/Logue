import AppKit
import SwiftUI

/// Centralized design tokens for the Logue app.
/// All color properties use `NSColor(name:dynamicProvider:)` so they
/// automatically resolve to the correct light/dark value when the
/// system appearance changes — no manual observation required.
enum AppThemeConstants {
    // MARK: - Dynamic Color Helper

    /// Creates a SwiftUI `Color` that resolves dynamically based on the
    /// current system appearance (light vs dark).
    private static func dynamicColor(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    /// Dynamic color with opacity variants.
    private static func dynamicColor(
        lightBase: NSColor, lightOpacity: Double,
        darkBase: NSColor, darkOpacity: Double
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? darkBase.withAlphaComponent(darkOpacity)
                : lightBase.withAlphaComponent(lightOpacity)
        })
    }

    // MARK: - Brand Colors

    /// Discord Blurple (#5865F2)
    /// Alias for `accent` — kept for backward compatibility.
    static let brandPrimary = accent
    static let brandSecondary = dynamicColor(light: "5CD1ED", dark: "5CD1ED")

    // MARK: - Accent Color

    static let accent = dynamicColor(light: "5865F2", dark: "5865F2")

    // MARK: - Semantic Status Colors

    static let success = dynamicColor(light: "448361", dark: "4F9768")
    static let warning = dynamicColor(light: "CB912F", dark: "C19138")
    static let error = dynamicColor(light: "D44C47", dark: "CD4945")
    static let info = dynamicColor(light: "5865F2", dark: "5865F2")

    // MARK: - Opacity Levels

    /// Subtle hover background (icon buttons, cards)
    static let hoverOpacity: Double = 0.07
    /// Active/selected state background
    static let activeOpacity: Double = 0.12
    /// Border stroke for selected items
    static let borderOpacity: Double = 0.3

    // MARK: - Opacity Scale

    /// Subtle backgrounds (card fills, inactive surfaces)
    static let opacitySubtle: Double = 0.04
    /// Light fills (hover backgrounds, chip fills)
    static let opacityLight: Double = 0.08
    /// Medium emphasis (borders, dividers, overlays)
    static let opacityMedium: Double = 0.15
    /// Strong emphasis (prominent but not full)
    static let opacityStrong: Double = 0.35
    /// Muted content (disabled, placeholder)
    static let opacityMuted: Double = 0.5

    // MARK: - Corner Radii

    static let radiusXSmall: CGFloat = 4
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10
    static let radiusXLarge: CGFloat = 14
    static let radiusPanel: CGFloat = 24

    // MARK: - Semantic Backgrounds

    /// Cards, panels, elevated surfaces
    static let surfaceBackground = dynamicColor(light: "F7F6F3", dark: "252525")
    /// Toolbars, status bars, chrome strips
    static let chromeBackground = dynamicColor(light: "F7F6F3", dark: "202020")
    /// Main content area background
    static let contentBackground = dynamicColor(light: "FFFFFF", dark: "191919")
    /// Text editors and input fields
    static let textInputBackground = dynamicColor(light: "F7F6F3", dark: "2F2F2F")

    /// Replaces Color(nsColor: .quaternarySystemFill)
    static let quaternaryFill = dynamicColor(
        lightBase: .black, lightOpacity: 0.04,
        darkBase: .white, darkOpacity: 0.04
    )

    /// Muted / secondary text
    static let mutedText = dynamicColor(light: "787774", dark: "9B9B9B")

    /// Separator lines
    static let separatorColor = dynamicColor(light: "E9E9E7", dark: "373737")

    // MARK: - Shadows

    static let shadowRadiusDefault: CGFloat = 4
    static let shadowRadiusHover: CGFloat = 8
    static let shadowOpacityDefault: Double = 0.05
    static let shadowOpacityHover: Double = 0.12

    // Panel / popup shadows
    static let panelShadowOpacity: Double = 0.20
    static let panelShadowRadius: CGFloat = 20
    static let panelShadowY: CGFloat = 8
    static let toastShadowOpacity: Double = 0.12
    static let toastShadowRadius: CGFloat = 12
    static let toastShadowY: CGFloat = 4

    // MARK: - Spacing

    static let paddingXSmall: CGFloat = 4
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 12
    static let paddingLarge: CGFloat = 16
    static let paddingXLarge: CGFloat = 20
    static let paddingXXLarge: CGFloat = 24
    static let sectionSpacing: CGFloat = 28

    // MARK: - Borders

    static let borderColor = dynamicColor(light: "E9E9E7", dark: "373737")

    // MARK: - Icon Sizes

    static let iconSmall: CGFloat = 12
    static let iconMedium: CGFloat = 16
    static let iconLarge: CGFloat = 20

    // MARK: - Editor Tokens

    static let editorHorizontalInset: CGFloat = 24
    static let editorVerticalInset: CGFloat = 36
    static let lineSpacingDefault: CGFloat = 4
    static let bulletDiameter: CGFloat = 5.5
    static let checkboxSize: CGFloat = 14
    static let checkboxCornerRadius: CGFloat = 3
    static let headingSizeH1: CGFloat = 15
    static let headingSizeH2: CGFloat = 9
    static let headingSizeH3: CGFloat = 4
    static let headingSpacingBeforeH1: CGFloat = 32
    static let headingSpacingBeforeH2: CGFloat = 24
    static let headingSpacingBeforeH3: CGFloat = 16
    static let headingSpacingAfter: CGFloat = 4
    static let listHeadIndent: CGFloat = 24
    static let listFirstLineIndent: CGFloat = 4
    static let blockQuoteIndent: CGFloat = 20
    static let menuIconPointSize: CGFloat = 13

    // Paragraph spacing
    static let bodyParagraphSpacing: CGFloat = 8
    static let listItemSpacing: CGFloat = 4

    // Per-level heading after-spacing
    static let headingSpacingAfterH1: CGFloat = 12
    static let headingSpacingAfterH2: CGFloat = 8
    static let headingSpacingAfterH3: CGFloat = 6

    // Block element spacing
    static let blockQuoteSpacingBefore: CGFloat = 8
    static let blockQuoteSpacingAfter: CGFloat = 8
    static let codeBlockSpacingBefore: CGFloat = 8
    static let codeBlockSpacingAfter: CGFloat = 8
    static let dividerSpacingBefore: CGFloat = 12
    static let dividerSpacingAfter: CGFloat = 12

    /// Nested list indentation per level
    static let listIndentPerLevel: CGFloat = 24

    // Table colors — Notion-style: visible borders, subtle header, transparent body
    static let tableBorderColor = dynamicColor(light: "E3E3E1", dark: "3A3A3A")
    static let tableHeaderFill = dynamicColor(light: "F7F6F3", dark: "252525")

    // Code block colors
    static let codeBlockBackground = dynamicColor(lightBase: .black, lightOpacity: opacitySubtle, darkBase: .white, darkOpacity: opacitySubtle)
    static let codeBlockBorder = dynamicColor(lightBase: .black, lightOpacity: opacityLight, darkBase: .white, darkOpacity: opacityLight)

    // MARK: - Semantic Colors

    static let pinnedColor = dynamicColor(light: "CA8A04", dark: "EAB308")
    static let actionBadgeColor = dynamicColor(light: "EA580C", dark: "FB923C")

    // MARK: - Category Colors (charts, badges, tags — visual differentiation)

    static let categoryPurple = dynamicColor(light: "7C5CFC", dark: "9B8AFF")
    static let categoryBlue = dynamicColor(light: "3B82F6", dark: "60A5FA")
    static let categoryYellow = dynamicColor(light: "CA8A04", dark: "EAB308")
    static let categoryGray = dynamicColor(light: "6B7280", dark: "9CA3AF")

    // MARK: - Speaker Colors (10-color palette for diarization)

    static let speakerBlurple = brandPrimary
    static let speakerGreen = dynamicColor(light: "16A34A", dark: "4ADE80")
    static let speakerOrange = dynamicColor(light: "EA580C", dark: "FB923C")
    static let speakerPurple = dynamicColor(light: "7C3AED", dark: "A78BFA")
    static let speakerPink = dynamicColor(light: "DB2777", dark: "F472B6")
    static let speakerYellow = dynamicColor(light: "CA8A04", dark: "FACC15")
    static let speakerCyan = dynamicColor(light: "0891B2", dark: "22D3EE")
    static let speakerMint = dynamicColor(light: "059669", dark: "34D399")
    static let speakerSky = brandSecondary
    static let speakerBrown = dynamicColor(light: "92400E", dark: "D97706")
    static let speakerTeal = dynamicColor(light: "0D9488", dark: "2DD4BF")

    // MARK: - Tag Colors (hash-based, consistent across app)

    static let tagPalette: [Color] = [
        dynamicColor(light: "5B5FC7", dark: "8B8FE8"), // indigo
        dynamicColor(light: "0E7C6B", dark: "34D399"), // emerald
        dynamicColor(light: "C2410C", dark: "FB923C"), // orange
        dynamicColor(light: "7C3AED", dark: "A78BFA"), // violet
        dynamicColor(light: "0284C7", dark: "38BDF8"), // sky
        dynamicColor(light: "B91C1C", dark: "F87171"), // rose
        dynamicColor(light: "4D7C0F", dark: "A3E635"), // lime
        dynamicColor(light: "BE185D", dark: "F472B6"), // pink
    ]

    /// Deterministic color for a tag string — same tag always maps to the same color.
    static func tagColor(for tag: String) -> Color {
        let hash = tag.lowercased().unicodeScalars.reduce(0) { acc, scalar in
            acc &* 31 &+ Int(scalar.value)
        }
        let index = abs(hash) % tagPalette.count
        return tagPalette[index]
    }

    // MARK: - Animation

    static let hoverDuration: Double = 0.15
    static let toggleDuration: Double = 0.18

    // MARK: - Command Center

    static let commandCenterBgStart = dynamicColor(light: "F7F6F3", dark: "202020")
    static let commandCenterBgEnd = dynamicColor(light: "F7F6F3", dark: "232323")
    static let commandCenterShadow = dynamicColor(
        lightBase: .black, lightOpacity: 0.15,
        darkBase: .black, darkOpacity: 0.6
    )

    // MARK: - Floating Island

    static let islandWidth: CGFloat = 680
    static let islandHeight: CGFloat = 520
    static let islandCornerRadius: CGFloat = 20
    static let islandBottomMargin: CGFloat = 12

    // Floating Island Typography
    static let islandTitle: Font = .system(size: 15, weight: .semibold)
    static let islandBody: Font = .system(size: 13, weight: .regular)
    static let islandCaption: Font = .system(size: 11, weight: .medium)
    static let islandLabel: Font = .system(size: 12, weight: .semibold)

    // MARK: - Chat Island (bottom-center)

    static let chatIslandWidth: CGFloat = 680
    static let chatIslandMinHeight: CGFloat = 180
    static let chatIslandMaxHeight: CGFloat = 600
    static let chatIslandCornerRadius: CGFloat = 20
    static let chatIslandBottomMargin: CGFloat = 40

    // MARK: - Recording Island (top-center, Dynamic Island style)

    static let recordingIslandWidth: CGFloat = 580
    static let recordingIslandMinHeight: CGFloat = 44
    static let recordingIslandMaxHeight: CGFloat = 300
    static let recordingIslandDefaultHeight: CGFloat = 140
    static let recordingIslandCornerRadius: CGFloat = 18
    static let recordingIslandTopMargin: CGFloat = 6

    // MARK: - Chat Typography

    static let chatInputFont: Font = .system(size: 15)
    static let chatMessageFont: Font = .system(size: 14)
    static let chatHeaderFont: Font = .system(size: 14, weight: .semibold)
}

// MARK: - NSColor Hex Extension

private extension NSColor {
    convenience init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch hexString.count {
        case 3:
            red = CGFloat((int >> 8) * 17) / 255
            green = CGFloat((int >> 4 & 0xF) * 17) / 255
            blue = CGFloat((int & 0xF) * 17) / 255
        case 6:
            red = CGFloat(int >> 16) / 255
            green = CGFloat(int >> 8 & 0xFF) / 255
            blue = CGFloat(int & 0xFF) / 255
        default:
            red = 0; green = 0; blue = 0
        }

        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

// MARK: - Color Hex Extension

public extension Color {
    /// Initialize a `Color` from a hexadecimal string.
    ///
    /// - Parameter hex: The hex string (e.g., "0771B1" or "#0771B1").
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)

        let alpha, red, green, blue: UInt64
        switch hexString.count {
        case 3: // RGB (12-bit)
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }

        #if canImport(AppKit)
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
        #else
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
        #endif
    }
}
