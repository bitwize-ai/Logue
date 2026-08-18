import Foundation

/// Action-item due dates, and the notifications scheduled against them.
///
/// Split out because it is the store's only dependency on `ReminderManager`: everything here
/// pairs a stored date with a system notification, and the two have to be changed together or a
/// reminder outlives the item it belongs to.
extension MeetingStore {
    func setActionItemDueDate(_ dueDate: Date?, itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }
        meetings[mIdx].actionItems[itemIndex].dueDate = dueDate
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func setActionItemReminder(itemID: UUID, in meetingID: UUID, reminderDate: Date) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }

        let item = meetings[mIdx].actionItems[itemIndex]
        let meetingTitle = meetings[mIdx].title

        // Cancel existing reminder if any
        if let existingNotifID = item.notificationID {
            ReminderManager.shared.cancelReminder(notificationID: existingNotifID)
        }

        // Schedule new reminder
        let notifID = ReminderManager.shared.scheduleReminder(
            for: item,
            at: reminderDate,
            meetingTitle: meetingTitle
        )

        meetings[mIdx].actionItems[itemIndex].reminderDate = reminderDate
        meetings[mIdx].actionItems[itemIndex].notificationID = notifID
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func cancelActionItemReminder(itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }

        if let notifID = meetings[mIdx].actionItems[itemIndex].notificationID {
            ReminderManager.shared.cancelReminder(notificationID: notifID)
        }

        meetings[mIdx].actionItems[itemIndex].reminderDate = nil
        meetings[mIdx].actionItems[itemIndex].notificationID = nil
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}
