import CoreAudio
import Foundation
import os.log

/// Watches the microphone a session is recording from, and says what to do when it goes away.
///
/// Property listeners rather than a polling loop, because macOS will tell us. The one timer here
/// exists for a different reason: a grace period has to *expire*, and nothing notifies us that a
/// device has stayed missing.
@MainActor
final class CaptureDeviceMonitor {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "CaptureDevice")

    private var onDecision: (@MainActor (DeviceLossPolicy.Decision, String) -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var graceTask: Task<Void, Never>?

    /// The device the session is recording from, and what kind of connection it is on.
    private var watchedDevice: AudioDeviceID?
    private var watchedName = ""
    private var watchedKind: InputDeviceKind = .unknown
    private var lostAt: TimeInterval?
    private var startedAt: Date?

    /// Begins watching whichever device is the current default input.
    ///
    /// `onDecision` is called with what to do and the name of the device now in use — never with
    /// `.keepWaiting` more than once per loss, so a caller can treat each call as news.
    func start(onDecision: @escaping @MainActor (DeviceLossPolicy.Decision, String) -> Void) {
        stop()
        self.onDecision = onDecision
        startedAt = Date()
        adoptCurrentDefaultInput()

        var address = CoreAudioProperty.devices
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.evaluate() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block
        )
        if status == noErr {
            listenerBlock = block
        } else {
            logger.error("Failed to observe the device list: \(status)")
        }
    }

    func stop() {
        graceTask?.cancel()
        graceTask = nil
        if let block = listenerBlock {
            var address = CoreAudioProperty.devices
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, block
            )
            listenerBlock = nil
        }
        onDecision = nil
        watchedDevice = nil
        watchedName = ""
        lostAt = nil
        startedAt = nil
    }
}

// MARK: - Watching

private extension CaptureDeviceMonitor {
    /// Records which device the session is on, and what kind of connection it is.
    func adoptCurrentDefaultInput() {
        guard let device = CoreAudioProperty.defaultInputDeviceID() else { return }
        watchedDevice = device
        watchedName = CoreAudioProperty.name(of: device) ?? "the microphone"
        watchedKind = InputDeviceKind.detect(
            transportType: CoreAudioProperty.transportType(of: device),
            deviceName: watchedName
        )
        lostAt = nil
        let name = watchedName
        let kind = String(describing: watchedKind)
        logger.info("Recording from \(name, privacy: .public) (\(kind, privacy: .public))")
    }

    var elapsed: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    func evaluate() {
        guard onDecision != nil, let device = watchedDevice else { return }

        let present = CoreAudioProperty.allDeviceIDs().contains(device)

        if present {
            guard lostAt != nil else { return } // Nothing was wrong.
            lostAt = nil
            graceTask?.cancel()
            graceTask = nil
            let name = watchedName
            logger.info("\(name, privacy: .public) came back")
            onDecision?(.resumeSameDevice, watchedName)
            return
        }

        guard let lost = lostAt else {
            // First observation of the loss. Start the clock and say we are waiting, once.
            lostAt = elapsed
            let name = watchedName
            logger.info("\(name, privacy: .public) disappeared — holding")
            onDecision?(.keepWaiting, watchedName)
            startGraceCountdown()
            return
        }

        let decision = DeviceLossPolicy.decide(
            lostAt: lost, now: elapsed, kind: watchedKind, hasReturned: false
        )
        guard decision == .fallBackToDefault else { return }

        graceTask?.cancel()
        graceTask = nil
        adoptCurrentDefaultInput()
        let name = watchedName
        logger.info("Falling back to \(name, privacy: .public)")
        onDecision?(.fallBackToDefault, watchedName)
    }

    /// Re-checks until the grace period expires. The device list listener fires when a device
    /// appears or disappears, but nothing fires to say one has *stayed* missing.
    func startGraceCountdown() {
        graceTask?.cancel()
        graceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppConstants.Delays.deviceLossPoll)
                guard !Task.isCancelled, let self else { return }
                evaluate()
                if lostAt == nil {
                    return
                }
            }
        }
    }
}
