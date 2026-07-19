import EventKit
import Foundation
import os.log

/// Lightweight wrapper around EventKit for reading macOS Calendar events.
/// All data stays on-device — no cloud sync initiated by Logue.
@Observable
@MainActor
final class CalendarManager {
    static let shared = CalendarManager()
    private init() {}

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "CalendarManager")
    private let store = EKEventStore()

    // MARK: - State

    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "calendarIntegrationEnabled")
    var upcomingEvents: [CalendarEvent] = []

    // MARK: - Authorization

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                logger.info("Calendar access granted")
                isEnabled = true
                UserDefaults.standard.set(true, forKey: "calendarIntegrationEnabled")
                refreshUpcomingEvents()
            } else {
                logger.info("Calendar access denied")
            }
        } catch {
            logger.error("Calendar access error: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: "calendarIntegrationEnabled")
        upcomingEvents = []
    }

    // MARK: - Fetch Events

    /// Fetch events for today and tomorrow.
    func refreshUpcomingEvents() {
        guard isAuthorized, isEnabled else {
            upcomingEvents = []
            return
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday) else { return }

        let predicate = store.predicateForEvents(
            withStart: Date.now,
            end: endOfTomorrow,
            calendars: nil
        )

        let ekEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        upcomingEvents = ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                calendarName: event.calendar?.title,
                calendarColorRGB: event.calendar?.cgColor.flatMap { Self.rgbFromCGColor($0) },
                url: event.url
            )
        }

        let count = upcomingEvents.count
        logger.info("Fetched \(count) upcoming events")
    }

    /// Fetch events for a specific date range.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard isAuthorized, isEnabled else { return [] }

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )

        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    location: event.location,
                    calendarName: event.calendar?.title,
                    calendarColorRGB: event.calendar?.cgColor.flatMap { Self.rgbFromCGColor($0) },
                    url: event.url
                )
            }
    }

    // MARK: - Create Calendar Event for Action Item

    /// Add an action item as a calendar reminder event.
    func createEvent(
        title: String,
        dueDate: Date,
        notes: String? = nil
    ) -> String? {
        createEvent(
            title: title,
            startDate: dueDate,
            endDate: Calendar.current.date(byAdding: .minute, value: 30, to: dueDate) ?? dueDate,
            notes: notes
        )
    }

    /// Create a calendar event with explicit start and end times (used by the agent's
    /// `create_calendar_event` tool). Adds a 15-minute reminder alert.
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil
    ) -> String? {
        guard isAuthorized else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        // Add alert 15 minutes before
        event.addAlarm(EKAlarm(relativeOffset: -900))

        do {
            try store.save(event, span: .thisEvent)
            logger.info("Created calendar event: \(event.eventIdentifier ?? "unknown")")
            return event.eventIdentifier
        } catch {
            logger.error("Failed to create event: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Update / Delete (Phase A capability gap closure)

    enum CalendarMutationError: Error {
        case notAuthorized
        case notFound
        case saveFailed(String)
    }

    /// Update an existing event by its EventKit identifier. Any nil parameter
    /// means "leave the existing value alone" — partial updates are supported
    /// so the agent can change just the title or just the notes if asked.
    func updateEvent(
        eventID: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil
    ) throws {
        guard isAuthorized else { throw CalendarMutationError.notAuthorized }
        guard let event = store.event(withIdentifier: eventID) else {
            throw CalendarMutationError.notFound
        }
        if let title {
            event.title = title
        }
        if let startDate {
            event.startDate = startDate
        }
        if let endDate {
            event.endDate = endDate
        }
        if let notes {
            event.notes = notes
        }
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw CalendarMutationError.saveFailed(error.localizedDescription)
        }
    }

    /// Delete an event by EventKit identifier. Removes the user-facing event;
    /// recurring series rules are honored via `.thisEvent`.
    func deleteEvent(eventID: String) throws {
        guard isAuthorized else { throw CalendarMutationError.notAuthorized }
        guard let event = store.event(withIdentifier: eventID) else {
            throw CalendarMutationError.notFound
        }
        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            throw CalendarMutationError.saveFailed(error.localizedDescription)
        }
    }

    /// Convert CGColor to an RGB tuple for Sendable storage.
    private static func rgbFromCGColor(_ color: CGColor) -> (red: Double, green: Double, blue: Double)? {
        guard let rgb = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3
        else { return nil }
        return (red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

// MARK: - Calendar Event Model

/// Lightweight representation of a calendar event for display in Logue.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let calendarName: String?
    /// Calendar color as RGB components (0–1). Use `.calendarCGColor` to convert to CGColor.
    let calendarColorRGB: (red: Double, green: Double, blue: Double)?
    let url: URL?

    /// Convenience to convert stored RGB back to CGColor for rendering.
    var calendarColor: CGColor? {
        guard let rgb = calendarColorRGB else { return nil }
        return CGColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }

    var isHappeningNow: Bool {
        Date.now >= startDate && Date.now <= endDate
    }

    var isStartingSoon: Bool {
        let minutesUntil = startDate.timeIntervalSince(Date.now) / 60
        return minutesUntil > 0 && minutesUntil <= 15
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }
}
