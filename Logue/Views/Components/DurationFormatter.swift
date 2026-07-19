import Foundation

/// Centralized time/duration formatting used across the app.
/// Previously duplicated in MeetingListView.formatTime and DailyDigestCard.formatDuration.
enum DurationFormatter {
    /// "2:05" style — minutes:seconds (for recording elapsed time).
    static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// "1h 25m" or "25m" style — for meeting durations.
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
