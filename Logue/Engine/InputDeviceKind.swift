import CoreAudio
import Foundation

/// What kind of connection a capture device is on, which is what decides how patient to be when it
/// disappears.
enum InputDeviceKind: Equatable {
    case wired
    case bluetooth
    case unknown

    /// Core Audio's transport type is authoritative; the name is a guess for the cases where the
    /// property is unavailable or says nothing useful, which is what aggregate and virtual devices
    /// report.
    static func detect(transportType: UInt32?, deviceName: String) -> InputDeviceKind {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypePCI:
            return .wired
        default:
            break
        }

        let lowered = deviceName.lowercased()
        let bluetoothMarkers = ["airpods", "bluetooth", "wireless", "beats", "buds"]
        if bluetoothMarkers.contains(where: lowered.contains) {
            return .bluetooth
        }
        return .unknown
    }

    /// How long to wait for this kind of device to come back before giving up on it.
    ///
    /// Bluetooth devices drop for a moment routinely — a codec renegotiation, a phone call arriving,
    /// walking past a microwave. Switching to the laptop microphone every time one hiccups is worse
    /// than a two-second gap in the recording. A device we could not identify is given the same
    /// benefit of the doubt, because the cost of being wrong that way round is smaller.
    var reconnectGrace: TimeInterval {
        switch self {
        case .bluetooth: 3.0
        case .wired: 2.0
        case .unknown: 3.0
        }
    }
}

/// What to do about a capture device that has gone away.
enum DeviceLossPolicy {
    enum Decision: Equatable {
        case keepWaiting
        case resumeSameDevice
        case fallBackToDefault
    }

    static func decide(
        lostAt: TimeInterval,
        now: TimeInterval,
        kind: InputDeviceKind,
        hasReturned: Bool
    ) -> Decision {
        // A device that is back is used, however long it took. Falling back to something else at
        // that point would swap a working device for another one for no reason.
        if hasReturned {
            return .resumeSameDevice
        }
        return now - lostAt >= kind.reconnectGrace ? .fallBackToDefault : .keepWaiting
    }
}
