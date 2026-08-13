import Accelerate
import Foundation
import os.log

/// Periodically reports how loud each capture source's contribution to the session timeline is.
///
/// A recording can be audible in its saved file and silent to the models that read the timeline —
/// the two are fed by different code paths, and only the second one matters for transcription and
/// diarization. When that happens the only symptom is an empty transcript, which says nothing about
/// which source failed. This says it.
struct TimelineContributionLog {
    /// How much audio a source contributes before its level is reported.
    private static let reportInterval = 16000 * 10 // ten seconds at the timeline's rate

    private var samplesSinceReport: [AudioSource: Int] = [:]
    private var energySinceReport: [AudioSource: Float] = [:]
    private var droppedConversions: [AudioSource: Int] = [:]

    mutating func record(_ samples: [Float], from source: AudioSource, logger: Logger) {
        guard !samples.isEmpty else { return }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        let count = (samplesSinceReport[source] ?? 0) + samples.count
        // Energy rather than a mean of means, so a short quiet buffer does not weigh as much as a
        // long loud one.
        let energy = (energySinceReport[source] ?? 0) + rms * rms * Float(samples.count)

        guard count >= Self.reportInterval else {
            samplesSinceReport[source] = count
            energySinceReport[source] = energy
            return
        }

        let meanRMS = (energy / Float(count)).squareRoot()
        let seconds = count / 16000
        logger.info(
            """
            Timeline: \(String(describing: source), privacy: .public) contributed \
            \(seconds, privacy: .public)s at RMS \(String(format: "%.5f", meanRMS), privacy: .public)
            """
        )
        if meanRMS < 0.0001 {
            logger.warning(
                "Timeline: \(String(describing: source), privacy: .public) is writing silence — the models will hear nothing from it"
            )
        }
        samplesSinceReport[source] = 0
        energySinceReport[source] = 0
    }

    /// A buffer that could not be converted never reaches the timeline at all, which is a different
    /// failure from a silent one and worth telling apart.
    mutating func recordDroppedConversion(from source: AudioSource, logger: Logger) {
        let count = (droppedConversions[source] ?? 0) + 1
        droppedConversions[source] = count
        if count == 1 || count % 200 == 0 {
            let name = String(describing: source)
            logger.warning(
                """
                Timeline: dropped \(count, privacy: .public) buffer(s) from \(name, privacy: .public)                 — conversion produced nothing
                """
            )
        }
    }
}
