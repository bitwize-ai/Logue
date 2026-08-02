import Darwin
import Foundation
import os.log

/// Accumulates a recording session's audio onto one 16 kHz mono timeline, placing every capture
/// source at the position it was actually heard at.
///
/// A meeting can have two streams arriving at once — system audio from the remote participants and
/// the local microphone — delivered as independent callbacks. Appending both to a single array puts
/// them in *arrival* order rather than in *time* order, and two consequences follow. Every timestamp
/// the batch transcriber and the diarizer derive from that array drifts further from the meeting the
/// longer it runs, because an hour of meeting has become two hours of buffer. And the capacity limit
/// arrives in half the wall-clock time, cutting the recording that can be processed in half.
///
/// So each source keeps its own cursor and writes where it belongs; samples that overlap are summed.
/// One source or five, the buffer is the meeting's timeline and `samples.count / sampleRate` is the
/// stretch of meeting it covers.
struct AudioTimelineMixer {
    /// Sample rate of the timeline. Sources are resampled to this before being written.
    let sampleRate: Double

    /// Most samples the timeline will hold. Audio past it is dropped rather than grown into, because
    /// the whole buffer is handed to the models in one piece and has to fit in memory to do that.
    let capacity: Int

    /// The mixed timeline, from the start of the session.
    private(set) var samples: [Float] = []

    /// Set once any audio has been dropped for want of capacity. The post-recording pass reads it to
    /// know its output speaks for only part of the session.
    private(set) var didDropAudio = false

    /// Where each source's next sample belongs, in timeline samples.
    private var cursors: [AudioSource: Int] = [:]

    init(sampleRate: Double, capacity: Int) {
        self.sampleRate = sampleRate
        self.capacity = max(0, capacity)
    }

    // MARK: - Capacity

    /// How many samples a machine with this much physical memory may hold.
    ///
    /// The buffer is held as Float32 and handed whole to Sortformer and Parakeet, so its ceiling is
    /// a memory question rather than a duration one — a fixed number of minutes is either wasteful
    /// on a large machine or reckless on a small one. A sixteenth of physical memory, floored and
    /// capped so neither end runs away, works out at roughly 2.3 hours on 8 GB and 4.6 hours from
    /// 16 GB up at the 16 kHz the models take.
    ///
    /// The result is a count of samples, so the sample rate does not enter into it — how many fit in
    /// a byte budget is the same number whatever they are played back at. It decides how many
    /// *seconds* that is, which is the caller's business.
    static func capacity(forPhysicalMemory physicalMemory: UInt64, availableMemory: UInt64? = nil) -> Int {
        var budget = physicalMemory / AppConstants.Diarization.audioBufferMemoryDivisor

        // Installed memory is not memory we can have. The buffer is handed to Parakeet and
        // Sortformer at the same time, on a machine that may already have an MLX model resident, so
        // where the OS will tell us what is actually free we take the smaller of the two shares.
        if let availableMemory {
            budget = min(budget, availableMemory / AppConstants.Diarization.audioBufferAvailableDivisor)
        }

        let bytes = min(
            max(budget, AppConstants.Diarization.audioBufferMinBytes),
            AppConstants.Diarization.audioBufferMaxBytes
        )
        return Int(bytes / UInt64(MemoryLayout<Float>.size))
    }

    /// Free and inactive physical memory, or nil if the kernel will not say.
    ///
    /// Inactive pages count: they are file-backed or already-written pages the OS reclaims on
    /// demand, so treating them as unavailable would floor the budget on any machine that has been
    /// awake for a while.
    static func availableSystemMemory() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * pageSize
    }

    // MARK: - Reading

    var isEmpty: Bool {
        samples.isEmpty
    }

    /// Seconds of session timeline the buffer covers.
    var duration: TimeInterval {
        sampleRate > 0 ? TimeInterval(Double(samples.count) / sampleRate) : 0
    }

    /// Seconds of timeline the buffer holds, or `nil` when it holds all of it. `nil` is what lets
    /// the post-recording pass replace the whole session's transcript; a value means it may only
    /// speak for that much of it.
    var heardDuration: TimeInterval? {
        didDropAudio ? duration : nil
    }

    // MARK: - Writing

    /// Declares where a source's next sample belongs on the session timeline.
    ///
    /// Call it when a source starts, including when one resumes: a capture device's own clock
    /// restarts from zero every time it is toggled, so only the session can say where its audio
    /// belongs. A source that never declares itself writes from the end of the timeline, which is
    /// where a source that starts now belongs anyway.
    mutating func beginSource(_ source: AudioSource, atSessionTime time: TimeInterval) {
        cursors[source] = max(0, Int((time * sampleRate).rounded()))
    }

    /// Mixes one source's samples into the timeline at that source's cursor.
    mutating func write(_ incoming: [Float], from source: AudioSource) {
        guard !incoming.isEmpty, capacity > 0 else { return }

        let start = cursors[source] ?? samples.count
        let end = start + incoming.count
        // The cursor advances even for audio that does not fit, so a source that outlives the
        // capacity limit stays correctly placed rather than piling up at the boundary.
        defer { cursors[source] = end }

        guard start < capacity else {
            didDropAudio = true
            return
        }
        if end > capacity {
            didDropAudio = true
        }

        let writable = min(end, capacity)
        if samples.isEmpty {
            samples.reserveCapacity(min(capacity, Int(sampleRate * 600)))
        }
        if samples.count < writable {
            // A source resuming after a mute leaves a gap, and the timeline is dense, so the gap
            // becomes real zeroed samples: ~230 MB an hour, allocated in one go on the actor that
            // draws the UI. Held deliberately — the models need the silence to place what follows
            // it, and a sparse timeline is a larger change than this fix — but a gap worth noticing
            // is worth logging, because it also spends capacity that real audio will then not have.
            let gap = writable - samples.count
            if gap > Int(sampleRate * 60) {
                let seconds = Int(Double(gap) / sampleRate)
                let megabytes = gap * MemoryLayout<Float>.size / 1_048_576
                os_log(
                    .info,
                    "Audio timeline: materialising a %{public}ds silent gap (~%{public}dMB)",
                    seconds, megabytes
                )
            }
            samples.append(contentsOf: repeatElement(0, count: gap))
        }

        for offset in 0 ..< (writable - start) {
            // Two people talking at once sums past full scale. Clamping distorts that moment;
            // halving every sample would instead cost signal on the far more common case of one
            // person talking, which is the one the models have to get right.
            samples[start + offset] = min(1, max(-1, samples[start + offset] + incoming[offset]))
        }
    }

    // MARK: - Clearing

    /// Hands over the timeline and resets for the next session.
    mutating func take() -> [Float] {
        let copy = samples
        removeAll()
        return copy
    }

    mutating func removeAll() {
        samples.removeAll(keepingCapacity: false)
        cursors.removeAll()
        didDropAudio = false
    }
}
