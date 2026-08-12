import CoreAudio
import Foundation
import os.log

/// Decides when a stretch of playback is long enough to mean a meeting rather than an alert sound.
///
/// Arming is one-way. Once the tap is running it stays running for the rest of the session, so a
/// pause in playback is not a reason to disarm and a resumption is not a second arming — tearing the
/// tap down and back up across a quiet stretch would open a `CaptureSegmentTimeline` placement for
/// each side of it and buy nothing.
struct PlaybackArmingDebounce {
    let debounce: TimeInterval

    private(set) var hasArmed = false
    private var playingSince: TimeInterval?

    init(debounce: TimeInterval) {
        self.debounce = debounce
    }

    /// Reports the current playback state. Returns `true` exactly once: on the observation that
    /// completes a sustained-playback window.
    mutating func observe(isPlaying: Bool, at now: TimeInterval) -> Bool {
        guard !hasArmed else { return false }

        guard isPlaying else {
            playingSince = nil
            return false
        }

        guard let since = playingSince else {
            playingSince = now
            return false
        }

        guard now - since >= debounce else { return false }

        hasArmed = true
        playingSince = nil
        return true
    }
}

/// Watches the default output device and reports when anything starts playing through it.
///
/// Two listeners rather than one: `kAudioDevicePropertyDeviceIsRunningSomewhere` says whether the
/// device we are watching is in use, and `kAudioHardwarePropertyDefaultOutputDevice` tells us when
/// the user changes outputs, at which point the first listener is on the wrong device and has to be
/// moved. Watching only the device the session started on would mean plugging in headphones
/// mid-call read as silence for the rest of the meeting.
@MainActor
@Observable
final class SystemAudioArmingMonitor {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SystemAudioArming")

    private var debounce = PlaybackArmingDebounce(
        debounce: AppConstants.Delays.systemAudioArmingDebounce
    )
    private var onArm: (@MainActor () -> Void)?
    private var watchedDevice: AudioDeviceID?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var pollTask: Task<Void, Never>?
    private var startedAt: Date?

    /// Begins watching. `onArm` fires at most once, on the main actor, and the monitor stops itself
    /// before it does — there is nothing left to watch for once the tap is up.
    func start(onArm: @escaping @MainActor () -> Void) {
        stop()
        self.onArm = onArm
        debounce = PlaybackArmingDebounce(debounce: AppConstants.Delays.systemAudioArmingDebounce)
        startedAt = Date()

        var address = CoreAudioProperty.defaultOutputDevice
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.attachToCurrentDefaultDevice()
                self?.evaluate()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block
        )
        if status == noErr {
            defaultDeviceListenerBlock = block
        } else {
            logger.error("Failed to observe the default output device: \(status)")
        }

        attachToCurrentDefaultDevice()

        // The property listener fires on transitions. If audio is already playing when recording
        // starts — the common case, since the user hits record after joining the call — there is no
        // transition to observe, so the debounce is also driven by a slow poll.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppConstants.Delays.systemAudioArmingPoll)
                // Ends the loop when the monitor goes away. `deinit` cannot cancel the task —
                // it is nonisolated and the handle is main-actor state — so the loop has to be
                // able to notice on its own that there is nothing left to poll for.
                guard !Task.isCancelled, let self else { return }
                evaluate()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        detachFromWatchedDevice()

        if let block = defaultDeviceListenerBlock {
            var address = CoreAudioProperty.defaultOutputDevice
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, block
            )
            defaultDeviceListenerBlock = nil
        }

        onArm = nil
        startedAt = nil
    }
}

// MARK: - Listening

private extension SystemAudioArmingMonitor {
    /// Re-reads playback state and feeds it to the debounce.
    func evaluate() {
        guard let startedAt, onArm != nil else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard debounce.observe(isPlaying: isDefaultOutputRunning(), at: elapsed) else { return }

        logger.info("Playback sustained — arming the system audio tap")
        let callback = onArm
        stop()
        callback?()
    }

    func isDefaultOutputRunning() -> Bool {
        guard let device = CoreAudioProperty.defaultOutputDeviceID() else { return false }
        var address = CoreAudioProperty.deviceIsRunningSomewhere
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)
        guard status == noErr else {
            logger.error("Failed to read whether the output device is running: \(status)")
            return false
        }
        return isRunning != 0
    }

    /// Moves the is-running listener onto whichever device is the default now.
    func attachToCurrentDefaultDevice() {
        guard let device = CoreAudioProperty.defaultOutputDeviceID() else { return }
        guard device != watchedDevice else { return }

        detachFromWatchedDevice()

        var address = CoreAudioProperty.deviceIsRunningSomewhere
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.evaluate() }
        }
        let status = AudioObjectAddPropertyListenerBlock(device, &address, nil, block)
        guard status == noErr else {
            logger.error("Failed to observe playback on the output device: \(status)")
            return
        }
        watchedDevice = device
        deviceListenerBlock = block
    }

    func detachFromWatchedDevice() {
        guard let device = watchedDevice, let block = deviceListenerBlock else { return }
        var address = CoreAudioProperty.deviceIsRunningSomewhere
        AudioObjectRemovePropertyListenerBlock(device, &address, nil, block)
        watchedDevice = nil
        deviceListenerBlock = nil
    }
}

// MARK: - Core Audio property addresses

/// The Core Audio property addresses the capture monitors read, in one place.
///
/// `AudioObjectPropertyAddress` has to be passed inout, so each caller needs its own mutable copy —
/// these are computed rather than stored so that no two call sites can share, and accidentally
/// mutate, one address.
enum CoreAudioProperty {
    static var defaultOutputDevice: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static var defaultInputDevice: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static var devices: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static var deviceIsRunningSomewhere: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        deviceID(for: defaultOutputDevice)
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        deviceID(for: defaultInputDevice)
    }

    private static func deviceID(for address: AudioObjectPropertyAddress) -> AudioDeviceID? {
        var address = address
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }
}
