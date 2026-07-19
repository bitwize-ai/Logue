import Accelerate
import AVFoundation
import CoreAudio
import Foundation
import os.log

/// Thread-safe holder for the audio buffer callback.
/// Allows the callback to be updated after the IO proc is already running.
/// @unchecked Sendable: os_unfair_lock provides thread-safety for the callback pointer.
///
/// IMPORTANT: Uses os_unfair_lock directly instead of OSAllocatedUnfairLock because
/// storing a function type in OSAllocatedUnfairLock's generic State causes the Swift
/// compiler to generate recursive calling-convention thunks (between @guaranteed and
/// @in_guaranteed representations) that overflow CoreAudio's 544K IO thread stack.
/// Direct lock usage avoids generic type bridging entirely.
final class AudioBufferCallbackHolder: @unchecked Sendable {
    private var _callback: ((AVAudioPCMBuffer) -> Void)?
    // nonisolated(unsafe): lock address is stable — stored in a heap-allocated class instance.
    nonisolated(unsafe) private var _lock = os_unfair_lock()

    var callback: ((AVAudioPCMBuffer) -> Void)? {
        get {
            os_unfair_lock_lock(&_lock)
            let cb = _callback
            os_unfair_lock_unlock(&_lock)
            return cb
        }
        set {
            os_unfair_lock_lock(&_lock)
            _callback = newValue
            os_unfair_lock_unlock(&_lock)
        }
    }
}

/// Captures system audio (from any meeting app) using Core Audio Taps API (macOS 14.2+).
/// Falls under "System Audio Recording Only" permission — no Screen Recording needed.
/// Streams raw AVAudioPCMBuffer to the caller — no chunking or downsampling.
/// SpeechTranscriberEngine handles format conversion internally.
@Observable
@MainActor
final class SystemAudioCapture {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SystemAudioCapture")

    // MARK: - State

    var isCapturing = false
    var currentTime: TimeInterval = 0
    var audioLevel: Float = 0

    /// The audio format of the capture tap. Available after `startCapture()` succeeds.
    private(set) var captureFormat: AVAudioFormat?

    // MARK: - Core Audio Internals

    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var timer: Timer?
    private var startTime: Date?

    /// Lock-protected audio level written from the IO thread, read by the MainActor timer.
    private let pendingAudioLevel = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// Sendable holder so the IO proc can read the latest callback dynamically.
    let audioCallback = AudioBufferCallbackHolder()

    /// Callback fired with every raw audio buffer from system audio.
    /// Can be set or updated after `startCapture()` — takes effect on the next IO cycle.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioCallback.callback }
        set { audioCallback.callback = newValue }
    }

    // MARK: - Capture Control

    /// Starts system audio capture using Core Audio Taps.
    /// Triggers "System Audio Recording Only" permission on first use only —
    /// the tap and aggregate device are kept alive between recordings to avoid re-prompting.
    /// Throws if permission is denied or tap creation fails.
    func startCapture() async throws {
        // Stop any running IO from a previous session (keeps tap + device alive)
        stopIO()

        do {
            // Reuse existing tap + aggregate device if available
            if tapID == nil || aggregateDeviceID == nil {
                // Step 1: Create a global system audio tap (mono for transcription)
                let tap = try createSystemAudioTap()
                tapID = tap

                // Step 2: Create a private aggregate device
                let device = try createAggregateDevice()
                aggregateDeviceID = device

                // Step 3: Add the tap to the aggregate device
                try addTapToAggregateDevice(tapID: tap, deviceID: device)

                // Step 4: Get audio format from the tap, then wait for device readiness
                let format = try getTapFormat(tapID: tap)
                captureFormat = format
                try await waitForDeviceReady(deviceID: device)
            }

            guard let device = aggregateDeviceID, let format = captureFormat else {
                throw SystemAudioError.invalidFormat
            }

            // Step 5: Install IO callback and start capturing
            try await startAudioDevice(deviceID: device, format: format)
        } catch {
            teardown()
            throw error
        }

        isCapturing = true
        startTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.currentTime = Date().timeIntervalSince(start)
                self.audioLevel = self.pendingAudioLevel.withLock { $0 }
            }
        }

        logger.info("System audio capture started (Core Audio Tap)")
    }

    /// Stops audio IO but keeps the tap and aggregate device alive for reuse.
    func stopCapture() {
        stopIO()
        logger.info("System audio capture stopped (tap preserved)")
    }

    /// Fully destroys all Core Audio resources including the tap and aggregate device.
    /// Call on app termination or when system audio is no longer needed.
    func teardown() {
        stopIO()

        if let deviceID = aggregateDeviceID {
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        aggregateDeviceID = nil

        if let tap = tapID {
            AudioHardwareDestroyProcessTap(tap)
        }
        tapID = nil

        captureFormat = nil
        logger.info("System audio tap fully torn down")
    }

    /// Stops the IO proc and timer but preserves the tap and aggregate device.
    private func stopIO() {
        isCapturing = false

        if let deviceID = aggregateDeviceID, let procID = ioProcID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        ioProcID = nil

        timer?.invalidate()
        timer = nil
        startTime = nil
        currentTime = 0
        audioLevel = 0
    }

    // MARK: - Core Audio Tap Setup

    private func createSystemAudioTap() throws -> AudioObjectID {
        // Global mono tap — captures ALL system audio, excludes nothing.
        // CATapDescription() default init does NOT enable global capture.
        // Must use the global tap initializer with empty exclude list.
        let description = CATapDescription(__monoGlobalTapButExcludeProcesses: [])
        description.name = "Logue-SystemAudio"
        description.muteBehavior = CATapMuteBehavior.unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)

        guard status == kAudioHardwareNoError else {
            logger.error("AudioHardwareCreateProcessTap failed: \(status, privacy: .public)")
            throw SystemAudioError.tapCreationFailed(status)
        }

        logger.info("Audio tap created: \(newTapID)")
        return newTapID
    }

    private func createAggregateDevice() throws -> AudioObjectID {
        let uid = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Logue-Aggregate",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
            kAudioAggregateDeviceMasterSubDeviceKey: 0,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
        ]

        var deviceID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

        guard status == kAudioHardwareNoError else {
            logger.error("AudioHardwareCreateAggregateDevice failed: \(status, privacy: .public)")
            throw SystemAudioError.aggregateDeviceFailed(status)
        }

        logger.info("Aggregate device created: \(deviceID)")
        return deviceID
    }

    private func addTapToAggregateDevice(tapID: AudioObjectID, deviceID: AudioObjectID) throws {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidSize = UInt32(MemoryLayout<CFString>.stride)
        var tapUID: CFString = "" as CFString

        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { ptr in
            AudioObjectGetPropertyData(tapID, &uidAddress, 0, nil, &uidSize, ptr)
        }

        guard uidStatus == kAudioHardwareNoError else {
            logger.error("Failed to get tap UID: \(uidStatus, privacy: .public)")
            throw SystemAudioError.tapAssignmentFailed(uidStatus)
        }

        var tapListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let tapArray = [tapUID] as CFArray
        let tapListSize = UInt32(MemoryLayout<CFArray>.stride)

        let status = withUnsafePointer(to: tapArray) { ptr in
            AudioObjectSetPropertyData(deviceID, &tapListAddress, 0, nil, tapListSize, ptr)
        }

        guard status == kAudioHardwareNoError else {
            logger.error("Failed to add tap to aggregate device: \(status, privacy: .public)")
            throw SystemAudioError.tapAssignmentFailed(status)
        }
    }

    /// Get the audio format directly from the tap (available immediately after tap creation).
    private func getTapFormat(tapID: AudioObjectID) throws -> AVAudioFormat {
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var streamDescription = AudioStreamBasicDescription()

        let status = AudioObjectGetPropertyData(
            tapID, &formatAddress, 0, nil, &formatSize, &streamDescription
        )

        guard status == kAudioHardwareNoError else {
            logger.error("Failed to get tap format: \(status, privacy: .public)")
            throw SystemAudioError.formatRetrievalFailed(status)
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw SystemAudioError.invalidFormat
        }

        logger.info(
            "Tap format: \(Int(streamDescription.mSampleRate))Hz, \(streamDescription.mChannelsPerFrame)ch, \(streamDescription.mBitsPerChannel)bit"
        )
        return format
    }

    /// Wait for the aggregate device to become ready before starting IO.
    private func waitForDeviceReady(deviceID: AudioObjectID) async throws {
        let maxPolls = AppConstants.Audio.maxDevicePollAttempts
        let pollInterval = AppConstants.Audio.devicePollIntervalNanos

        for poll in 1 ... maxPolls {
            var isAlive: UInt32 = 0
            var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            var aliveAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let aliveStatus = AudioObjectGetPropertyData(
                deviceID, &aliveAddress, 0, nil, &aliveSize, &isAlive
            )
            if aliveStatus == kAudioHardwareNoError, isAlive == 1 {
                logger.debug("Aggregate device ready after \(poll) polls")
                return
            }
            if poll == maxPolls {
                logger.warning("Device did not become ready within timeout, proceeding anyway")
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }

    private func startAudioDevice(deviceID: AudioObjectID, format: AVAudioFormat) async throws {
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0 else {
            throw SystemAudioError.invalidFormat
        }

        let isFloat = format.commonFormat == .pcmFormatFloat32 || format.commonFormat == .pcmFormatFloat64

        // Capture the Sendable callback holder — reads the latest callback on each IO cycle.
        let callbackHolder = audioCallback

        var procID: AudioDeviceIOProcID?
        // AudioDeviceIOBlock params: (inNow, inInputData, inInputTime, outOutputData, inOutputTime)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { [weak self] _, inputData, _, _, _ in
            let bufferList = inputData.pointee
            let rawBuffer = bufferList.mBuffers

            guard let data = rawBuffer.mData, rawBuffer.mDataByteSize > 0 else { return }

            let frameCount = AVAudioFrameCount(rawBuffer.mDataByteSize / bytesPerFrame)
            guard frameCount > 0 else { return }
            // Validate that calculated frame count doesn't exceed actual data size
            guard Int(frameCount) * Int(bytesPerFrame) <= Int(rawBuffer.mDataByteSize) else { return }
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            else { return }
            pcmBuffer.frameLength = frameCount

            // Copy only the bytes that fit within the allocated buffer to prevent overflow
            // (e.g., if mDataByteSize isn't evenly divisible by bytesPerFrame, or format changed)
            let safeByteCount = min(Int(rawBuffer.mDataByteSize), Int(frameCount) * Int(bytesPerFrame))
            memcpy(pcmBuffer.audioBufferList.pointee.mBuffers.mData, data, safeByteCount)

            // Calculate audio level (RMS) via Accelerate for the real-time audio path
            let count = Int(pcmBuffer.frameLength)
            var rms: Float = 0

            if isFloat, let channelData = pcmBuffer.floatChannelData, count > 0 {
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(count))
            } else if let channelData = pcmBuffer.int16ChannelData, count > 0 {
                let samples = UnsafeBufferPointer(start: channelData[0], count: count)
                let sum = samples.reduce(Float(0)) { acc, sample in
                    let normalized = Float(sample) / Float(Int16.max)
                    return acc + normalized * normalized
                }
                rms = sqrt(sum / Float(count))
            }

            let normalized = AudioLevelNormalizer.normalize(rms)
            self?.pendingAudioLevel.withLock { $0 = normalized }

            // Read the latest callback dynamically (supports post-start updates)
            callbackHolder.callback?(pcmBuffer)
        }

        guard let procID, status == noErr else {
            logger.error("AudioDeviceCreateIOProcIDWithBlock failed: \(status, privacy: .public)")
            throw SystemAudioError.ioStartFailed(status)
        }

        ioProcID = procID

        // Retry AudioDeviceStart with exponential backoff — the aggregate device may not
        // be fully ready for IO immediately after tap attachment, even if it reports isAlive=1.
        let maxRetries = AppConstants.Audio.maxDeviceStartRetries
        var currentDelay: UInt64 = AppConstants.Delays.audioDeviceStartInitialDelayNanos

        for attempt in 1 ... maxRetries {
            let startStatus = AudioDeviceStart(deviceID, procID)
            if startStatus == noErr {
                logger.info("Audio IO proc started on device \(deviceID) (attempt \(attempt))")
                return
            }

            if attempt == maxRetries {
                AudioDeviceDestroyIOProcID(deviceID, procID)
                ioProcID = nil
                logger.error("AudioDeviceStart failed after \(maxRetries) attempts: \(startStatus, privacy: .public)")
                throw SystemAudioError.ioStartFailed(startStatus)
            }

            logger.debug("AudioDeviceStart attempt \(attempt) failed (\(startStatus)), retrying in \(currentDelay / 1_000_000)ms...")
            try await Task.sleep(nanoseconds: currentDelay)
            currentDelay = min(currentDelay * 2, AppConstants.Delays.audioDeviceStartMaxDelayNanos)
        }
    }
}

// MARK: - Error Types

enum SystemAudioError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case tapAssignmentFailed(OSStatus)
    case formatRetrievalFailed(OSStatus)
    case invalidFormat
    case ioStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .tapCreationFailed(status):
            "Failed to create audio tap (error \(status)). System audio permission may be required."
        case let .aggregateDeviceFailed(status):
            "Failed to create aggregate audio device (error \(status))."
        case let .tapAssignmentFailed(status):
            "Failed to configure audio tap (error \(status))."
        case let .formatRetrievalFailed(status):
            "Failed to retrieve audio format (error \(status))."
        case .invalidFormat:
            "Invalid audio format from system audio tap."
        case let .ioStartFailed(status):
            "Failed to start audio capture (error \(status))."
        }
    }
}
