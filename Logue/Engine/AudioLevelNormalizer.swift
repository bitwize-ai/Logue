import Foundation

/// Converts raw RMS amplitude to a perceptually-scaled 0–1 value using dB scaling.
/// This matches human hearing perception — quiet sounds become more visible on level meters.
enum AudioLevelNormalizer {
    /// Maps raw RMS (0–1) to a normalized 0–1 level using logarithmic (dB) scaling.
    /// - `-50 dB` (RMS ≈ 0.003) → `0.0` (silence)
    /// - `-20 dB` (RMS ≈ 0.1)   → `0.6` (moderate)
    /// - `0 dB`   (RMS = 1.0)    → `1.0` (maximum)
    static func normalize(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let minDb: Float = -50
        let clamped = max(db, minDb)
        return min(1.0, (clamped - minDb) / -minDb)
    }
}
