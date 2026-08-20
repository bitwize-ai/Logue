import CoreAudio
import Foundation
@testable import Logue
import Testing

@Suite("Device loss policy")
struct DeviceLossPolicyTests {
    // MARK: - Kind detection

    @Test("Core Audio's transport type is believed over the name")
    func transportTypeWins() {
        #expect(
            InputDeviceKind.detect(transportType: kAudioDeviceTransportTypeBluetooth, deviceName: "Studio Mic")
                == .bluetooth
        )
        #expect(
            InputDeviceKind.detect(transportType: kAudioDeviceTransportTypeBuiltIn, deviceName: "AirPods Pro")
                == .wired
        )
    }

    @Test("The name is a fallback when the transport type is unavailable")
    func nameIsFallback() {
        #expect(InputDeviceKind.detect(transportType: nil, deviceName: "Charan's AirPods Pro") == .bluetooth)
        #expect(InputDeviceKind.detect(transportType: nil, deviceName: "Bluetooth Headset") == .bluetooth)
        #expect(InputDeviceKind.detect(transportType: nil, deviceName: "MacBook Pro Microphone") == .unknown)
    }

    @Test("An unrecognised transport type still falls back to the name")
    func unknownTransportFallsBackToName() {
        #expect(
            InputDeviceKind.detect(transportType: kAudioDeviceTransportTypeAggregate, deviceName: "My AirPods")
                == .bluetooth
        )
    }

    @Test("Bluetooth gets a longer grace period than wired")
    func bluetoothGetsMoreGrace() {
        #expect(InputDeviceKind.bluetooth.reconnectGrace > InputDeviceKind.wired.reconnectGrace)
    }

    @Test("An unknown device is treated as patiently as a Bluetooth one")
    func unknownIsPatient() {
        #expect(InputDeviceKind.unknown.reconnectGrace >= InputDeviceKind.bluetooth.reconnectGrace)
    }

    // MARK: - Policy

    @Test("A device that comes back inside the grace period is resumed")
    func returnsInsideGraceResumes() {
        let decision = DeviceLossPolicy.decide(lostAt: 10, now: 11, kind: .bluetooth, hasReturned: true)
        #expect(decision == .resumeSameDevice)
    }

    @Test("A device still missing inside the grace period is waited for")
    func missingInsideGraceWaits() {
        let decision = DeviceLossPolicy.decide(lostAt: 10, now: 11, kind: .bluetooth, hasReturned: false)
        #expect(
            decision == .keepWaiting,
            "AirPods drop for a second constantly; switching away is worse than a short gap"
        )
    }

    @Test("A device still missing past the grace period falls back")
    func missingPastGraceFallsBack() {
        let decision = DeviceLossPolicy.decide(lostAt: 10, now: 20, kind: .bluetooth, hasReturned: false)
        #expect(decision == .fallBackToDefault)
    }

    @Test("A wired device falls back sooner than a Bluetooth one")
    func wiredFallsBackSooner() {
        let atTwoAndAHalf = 12.5
        #expect(
            DeviceLossPolicy.decide(lostAt: 10, now: atTwoAndAHalf, kind: .wired, hasReturned: false)
                == .fallBackToDefault
        )
        #expect(
            DeviceLossPolicy.decide(lostAt: 10, now: atTwoAndAHalf, kind: .bluetooth, hasReturned: false)
                == .keepWaiting
        )
    }

    @Test("A device returning after the grace period has passed is still resumed")
    func lateReturnIsStillResumed() {
        let decision = DeviceLossPolicy.decide(lostAt: 10, now: 30, kind: .wired, hasReturned: true)
        #expect(
            decision == .resumeSameDevice,
            "if it is back, use it — falling back to a device we do not need helps nobody"
        )
    }
}
