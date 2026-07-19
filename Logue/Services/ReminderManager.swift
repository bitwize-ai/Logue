import Foundation
import os.log
import UserNotifications

/// Manages scheduling and cancellation of local macOS notifications for action item reminders.
@MainActor
final class ReminderManager {
    static let shared = ReminderManager()
    private init() {}

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "ReminderManager")
    private let center = UNUserNotificationCenter.current()

    // MARK: - Authorization

    /// Request notification permission. Call once at app launch.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [logger] granted, error in
            if granted {
                logger.info("Notification permission granted")
            } else if let error {
                logger.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Notification permission denied")
            }
        }
    }

    /// Check current authorization status.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Scheduling

    /// Schedule a reminder notification for an action item.
    /// Returns the notification identifier for later cancellation.
    @discardableResult
    func scheduleReminder(
        for item: ActionItem,
        at date: Date,
        meetingTitle: String
    ) -> String {
        let notificationID = "action-item-\(item.id.uuidString)"

        // Don't schedule if the date is in the past
        guard date > Date.now else {
            logger.warning("Skipping reminder for past date: \(date, privacy: .public)")
            return notificationID
        }

        let content = UNMutableNotificationContent()
        content.title = "Action Item Reminder"
        content.subtitle = meetingTitle
        content.body = item.title
        if let assignee = item.assignee {
            content.body += " (Assigned to: \(assignee))"
        }
        content.sound = .default
        content.categoryIdentifier = "ACTION_ITEM_REMINDER"
        content.userInfo = [
            "actionItemID": item.id.uuidString,
            "type": "actionItemReminder",
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule reminder: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Reminder scheduled: \(notificationID) at \(date, privacy: .public)")
            }
        }

        return notificationID
    }

    /// Cancel a previously scheduled reminder.
    func cancelReminder(notificationID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        logger.info("Reminder cancelled: \(notificationID)")
    }

    /// Cancel all reminders for a specific action item.
    func cancelReminder(for itemID: UUID) {
        let notificationID = "action-item-\(itemID.uuidString)"
        cancelReminder(notificationID: notificationID)
    }

    /// Cancel all Logue reminders.
    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
        logger.info("All reminders cancelled")
    }

    // MARK: - Notification Categories

    /// Register notification action categories. Call once at app launch.
    func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: "MARK_COMPLETE",
            title: "Mark Complete",
            options: []
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_1H",
            title: "Snooze 1 Hour",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "ACTION_ITEM_REMINDER",
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }
}
