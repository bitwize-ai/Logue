import CoreLocation
import Foundation
import MLXLMCommon
import os.log

/// One-shot CoreLocation lookup. Returns the user's current coordinates +
/// a reverse-geocoded human-readable address. Used by the agent for
/// "what's the weather here", "what restaurants are nearby", etc.
///
/// Sandbox-safe via `com.apple.security.personal-information.location`
/// + `NSLocationUsageDescription` (added to entitlements + Info.plist).
///
/// `.sensitive` clearance — location is privacy-relevant; the user should
/// approve the disclosure before the LLM gets coordinates back.
struct GetLocationTool: AgentTool {
    let name = "get_location"
    let description = """
    Get the user's current location. Returns latitude, longitude, and a \
    reverse-geocoded address (city, region, country). Use only when the \
    request actually depends on where the user is — weather, nearby \
    places, time-zone-aware suggestions. Don't call speculatively.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "include_address": AgentToolSpec.stringParam(
                    "Set to 'false' to skip reverse-geocoding (coords only). Default: true."
                ),
            ]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let includeAddress = (arguments["include_address"] as? String)?.lowercased() != "false"

        let location: CLLocation
        do {
            location = try await OneShotLocator.shared.requestOnce()
        } catch OneShotLocator.LocationError.denied {
            throw AgentToolError.executionFailed(
                "Location access not granted. Approve it in System Settings → Privacy → Location Services."
            )
        } catch OneShotLocator.LocationError.timedOut {
            throw AgentToolError.executionFailed("Location lookup timed out — try again in a moment.")
        } catch OneShotLocator.LocationError.servicesDisabled {
            throw AgentToolError.executionFailed("Location Services is disabled system-wide.")
        } catch {
            throw AgentToolError.executionFailed("Couldn't get location: \(error.localizedDescription)")
        }

        var output = String(
            format: "Coordinates: %.5f, %.5f (accuracy ~%.0fm)",
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy
        )

        if includeAddress {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let place = placemarks.first {
                    let parts = [
                        place.subLocality,
                        place.locality,
                        place.administrativeArea,
                        place.country,
                    ].compactMap { $0 }.filter { !$0.isEmpty }
                    if !parts.isEmpty {
                        output += "\nAddress: \(parts.joined(separator: ", "))"
                    }
                }
            } catch {
                output += "\n(reverse-geocoding failed: \(error.localizedDescription))"
            }
        }

        return output
    }
}

// MARK: - OneShotLocator

/// Minimal wrapper around `CLLocationManager` exposing a single async
/// `requestOnce()` call. Unlike `CLLocationUpdate.liveUpdates`, this gives
/// us deterministic one-shot semantics + a 6-second timeout so the agent
/// loop doesn't hang if the user denies / has flaky GPS.
final class OneShotLocator: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = OneShotLocator()

    enum LocationError: Error {
        case denied
        case timedOut
        case servicesDisabled
    }

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "OneShotLocator")
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private let lock = NSLock()

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Returns one location fix or throws. Auto-times out after 6 seconds.
    func requestOnce(timeout: TimeInterval = 6) async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            // If a previous request is in flight, fail it cleanly so the new
            // one doesn't deadlock on a stale continuation.
            if let prior = continuation {
                prior.resume(throwing: LocationError.timedOut)
            }
            continuation = cont
            lock.unlock()

            // Permission check + request must happen on the main thread.
            DispatchQueue.main.async {
                let status = self.manager.authorizationStatus
                switch status {
                case .denied, .restricted:
                    self.complete(.failure(LocationError.denied))
                    return
                case .notDetermined:
                    self.manager.requestWhenInUseAuthorization()
                default: break
                }
                self.manager.requestLocation()
            }

            // Timeout watchdog.
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.lock.lock()
                let stillWaiting = self.continuation != nil
                self.lock.unlock()
                if stillWaiting {
                    self.complete(.failure(LocationError.timedOut))
                }
            }
        }
    }

    private func complete(_ result: Result<CLLocation, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        guard let cont else { return }
        switch result {
        case let .success(loc): cont.resume(returning: loc)
        case let .failure(err): cont.resume(throwing: err)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        complete(.success(loc))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("CoreLocation failed: \(error.localizedDescription, privacy: .public)")
        complete(.failure(error))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // If the user just denied while we were waiting on prompt, fail fast.
        switch manager.authorizationStatus {
        case .denied, .restricted:
            complete(.failure(LocationError.denied))
        default: break
        }
    }
}
