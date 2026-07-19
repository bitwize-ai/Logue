import Foundation

/// Generic date-grouping logic reused by document and meeting list views.
///
/// Usage:
/// ```
/// let groups = DateGroupingHelper.group(meetings, by: \.createdAt)
/// // returns [(label: "Today", items: [...]), (label: "Yesterday", items: [...]), ...]
/// ```
enum DateGroupingHelper {
    struct Group<T> {
        let label: String
        let items: [T]
    }

    /// Groups items by date proximity (Today, Yesterday, Previous 7 Days, Previous 30 Days, Older).
    /// Items within each group preserve the input order.
    static func group<T>(_ items: [T], by dateKeyPath: KeyPath<T, Date>) -> [Group<T>] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: startOfToday)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: startOfToday)

        var today: [T] = []
        var yesterday: [T] = []
        var previous7Days: [T] = []
        var previous30Days: [T] = []
        var older: [T] = []

        for item in items {
            let date = item[keyPath: dateKeyPath]
            if cal.isDateInToday(date) {
                today.append(item)
            } else if cal.isDateInYesterday(date) {
                yesterday.append(item)
            } else if let cutoff = sevenDaysAgo, date >= cutoff {
                previous7Days.append(item)
            } else if let cutoff = thirtyDaysAgo, date >= cutoff {
                previous30Days.append(item)
            } else {
                older.append(item)
            }
        }

        var result: [Group<T>] = []
        if !today.isEmpty {
            result.append(Group(label: "Today", items: today))
        }
        if !yesterday.isEmpty {
            result.append(Group(label: "Yesterday", items: yesterday))
        }
        if !previous7Days.isEmpty {
            result.append(Group(label: "Previous 7 Days", items: previous7Days))
        }
        if !previous30Days.isEmpty {
            result.append(Group(label: "Previous 30 Days", items: previous30Days))
        }
        if !older.isEmpty {
            result.append(Group(label: "Older", items: older))
        }
        return result
    }
}
