import Foundation
import SwiftUI

// MARK: - Speaker

/// Represents a unique speaker identified through diarization.
/// Persisted as part of MeetingNote's speaker data (Codable).
struct Speaker: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    let createdAt: Date
    var embedding: [Float]?

    var displayColor: Color {
        Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        color: Color = AppThemeConstants.brandPrimary,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.name = name
        createdAt = Date()
        self.embedding = embedding

        let nsColor = NSColor(color)
        let rgbColor = nsColor.usingColorSpace(.sRGB) ?? NSColor.blue
        colorRed = Double(rgbColor.redComponent)
        colorGreen = Double(rgbColor.greenComponent)
        colorBlue = Double(rgbColor.blueComponent)
    }

    static func generateColor(for index: Int) -> Color {
        let colors: [Color] = [
            AppThemeConstants.speakerBlurple,
            AppThemeConstants.speakerGreen,
            AppThemeConstants.speakerOrange,
            AppThemeConstants.speakerPurple,
            AppThemeConstants.speakerPink,
            AppThemeConstants.speakerYellow,
            AppThemeConstants.speakerCyan,
            AppThemeConstants.speakerMint,
            AppThemeConstants.speakerSky,
            AppThemeConstants.speakerBrown,
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Speaker Segment

/// A time-range within a meeting transcript attributed to a specific speaker.
struct SpeakerSegment: Identifiable, Codable, Sendable {
    let id: String
    let speakerId: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    let confidence: Float
    var embedding: [Float]?

    var duration: TimeInterval {
        endTime - startTime
    }

    init(
        id: String = UUID().uuidString,
        speakerId: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String = "",
        confidence: Float = 0.0,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.embedding = embedding
    }
}

// MARK: - Diarization Config

/// Configuration for speaker diarization.
struct DiarizationConfig: Sendable {
    var isEnabled: Bool = true
    var clusteringThreshold: Float = 0.7
    var minSegmentDuration: TimeInterval = 0.5
    var maxSpeakers: Int?

    static let `default` = DiarizationConfig()
}
