import SwiftUI

// MARK: - Upcoming Events Card

/// Displays upcoming calendar events with record buttons.
struct OverviewUpcomingEventsCard: View {
    let calendarManager: CalendarManager
    let onStartMeeting: (CalendarEvent) -> Void

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 10) {
                CardSectionHeader(icon: "calendar", title: "Upcoming")
                let events = Array(calendarManager.upcomingEvents.prefix(4))
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    upcomingEventRow(event)
                    if index < events.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func upcomingEventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 10) {
            Group {
                if event.isHappeningNow {
                    Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(AppThemeConstants.error)
                } else {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                Text("\(event.durationMinutes) min").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            // S-N5: Validate URL scheme
            if let url = event.url, url.scheme == "https" || url.scheme == "http" {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill").font(.caption2).foregroundStyle(AppThemeConstants.success)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join meeting")
            }
            Button { onStartMeeting(event) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "record.circle")
                        .font(.caption2)
                    Text("Record")
                        .font(.caption2.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .tint(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.accent)
            .controlSize(.mini)
            .accessibilityLabel("Record meeting")
        }
    }
}

// MARK: - Weekly Compact Card

/// Compact card showing this week's meeting count and time trend.
struct OverviewWeeklyCard: View {
    let insights: InsightsStatsProvider

    var body: some View {
        let weeklyMeetings = insights.weeklyActivity.reduce(0) { $0 + $1.meetingCount }
        let trend = insights.meetingTimeTrend
        InsightCardShell {
            VStack(alignment: .leading, spacing: 8) {
                CardSectionHeader(icon: "calendar.badge.clock", title: "This Week")
                Text("\(weeklyMeetings)")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text("Meetings")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    if trend.lastWeekSeconds > 0 || trend.thisWeekSeconds > 0 {
                        Image(systemName: trend.deltaPercent >= 0
                            ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8))
                            .foregroundStyle(trend.deltaPercent >= 0 ? AppThemeConstants.success : AppThemeConstants.warning)
                    }
                    Text(trend.thisWeekFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Monthly Compact Card

/// Compact card showing this month's meeting count and total duration.
struct OverviewMonthlyCard: View {
    let insights: InsightsStatsProvider

    var body: some View {
        let monthly = insights.monthlyStats
        InsightCardShell {
            VStack(alignment: .leading, spacing: 8) {
                CardSectionHeader(icon: "calendar", title: "This Month")
                Text("\(monthly.meetingCount)")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text("Meetings")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(monthly.totalFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Meeting Types Card

/// Bar chart card showing breakdown of meetings by template type.
struct OverviewMeetingTypesCard: View {
    let insights: InsightsStatsProvider

    private static let templateColors: [MeetingTemplate: Color] = [
        .general: AppThemeConstants.accent,
        .oneOnOne: AppThemeConstants.categoryPurple,
        .standup: AppThemeConstants.warning,
        .interview: .cyan,
        .brainstorm: AppThemeConstants.pinnedColor,
        .presentation: AppThemeConstants.success,
    ]

    var body: some View {
        let breakdownMap = Dictionary(
            uniqueKeysWithValues: insights.meetingBreakdown.map { ($0.template, $0) }
        )
        let totalMeetings = max(
            insights.meetingBreakdown.reduce(0) { $0 + $1.count }, 1
        )
        InsightCardShell {
            VStack(alignment: .leading, spacing: 10) {
                CardSectionHeader(icon: "chart.bar.doc.horizontal", title: "Meeting Types")
                VStack(spacing: 8) {
                    ForEach(MeetingTemplate.allCases) { template in
                        let count = breakdownMap[template]?.count ?? 0
                        let pct = Double(count) / Double(totalMeetings) * 100
                        let color = Self.templateColors[template] ?? AppThemeConstants.categoryGray
                        meetingTypeRow(template: template, count: count, percentage: pct, color: color)
                    }
                }
            }
        }
    }

    private func meetingTypeRow(
        template: MeetingTemplate, count: Int, percentage: Double, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: template.iconName)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(template.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(count > 0 ? color : color.opacity(0.3))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(AppThemeConstants.activeOpacity))
                        .frame(height: 4)
                    if count > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * (percentage / 100), height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
    }
}
