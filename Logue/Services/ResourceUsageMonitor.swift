import Darwin
import Foundation

/// Samples CPU and memory usage for the current process using mach kernel APIs.
/// Updates every second and keeps a 60-second rolling history for sparklines.
///
/// CPU: delta-based (Δprocess_cpu_time / Δwall_time × 100), matching Activity Monitor.
/// Memory: phys_footprint from MACH_TASK_BASIC_INFO, matching Activity Monitor's Memory column.
@Observable
@MainActor
final class ResourceUsageMonitor {
    static let shared = ResourceUsageMonitor()

    // MARK: - Public state

    private(set) var cpuPercent: Double = 0
    private(set) var memoryBytes: UInt64 = 0
    let totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [UInt64] = []

    // MARK: - Private state

    private let historyCapacity = 60
    private var timer: Timer?

    /// Accumulated process CPU time (user + system) from the previous sample, in nanoseconds.
    private var previousCPUNanos: UInt64 = 0
    /// Wall-clock time of the previous sample, converted to nanoseconds.
    private var previousWallNanos: UInt64 = 0
    private var timebaseInfo = mach_timebase_info_data_t()

    // MARK: - Lifecycle

    private init() {
        mach_timebase_info(&timebaseInfo)
    }

    func start() {
        guard timer == nil else { return }
        sample()
        let sampleTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(sampleTimer, forMode: .common)
        timer = sampleTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Sampling

    private func sample() {
        cpuPercent = currentCPUUsage()
        memoryBytes = Self.currentMemoryUsage()

        cpuHistory.append(cpuPercent)
        memoryHistory.append(memoryBytes)
        if cpuHistory.count > historyCapacity {
            cpuHistory.removeFirst()
        }
        if memoryHistory.count > historyCapacity {
            memoryHistory.removeFirst()
        }
    }

    // MARK: - CPU (delta-based, matches Activity Monitor)

    /// Returns CPU% for this process since the last sample.
    /// Matches Activity Monitor: can exceed 100% on multi-core machines when multiple
    /// threads are busy (e.g. 200% = two cores fully utilised).
    private func currentCPUUsage() -> Double {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &taskInfo, size) == size else {
            return cpuPercent // keep last known value on failure
        }

        let cpuNanos = taskInfo.pti_total_user + taskInfo.pti_total_system
        let wallNanos = machTimeToNanos(mach_absolute_time())

        defer {
            previousCPUNanos = cpuNanos
            previousWallNanos = wallNanos
        }

        guard previousWallNanos > 0, wallNanos > previousWallNanos else { return 0 }

        let cpuDelta = cpuNanos &- previousCPUNanos
        let wallDelta = wallNanos - previousWallNanos

        return Double(cpuDelta) / Double(wallDelta) * 100.0
    }

    // MARK: - Memory (phys_footprint, matches Activity Monitor)

    private static func currentMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    // MARK: - Helpers

    private func machTimeToNanos(_ machTime: UInt64) -> UInt64 {
        // Use Double to avoid UInt64 overflow; nanosecond precision is sufficient here.
        UInt64(Double(machTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom))
    }
}

// MARK: - Formatting helpers

extension ResourceUsageMonitor {
    var memoryUsedFormatted: String {
        formatBytes(memoryBytes)
    }

    var totalMemoryFormatted: String {
        formatBytes(totalMemoryBytes)
    }

    var memoryFraction: Double {
        totalMemoryBytes > 0 ? Double(memoryBytes) / Double(totalMemoryBytes) : 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}
