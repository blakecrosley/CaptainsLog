import Foundation

enum CompanionSnapshotBuilder {
    static func makeSnapshot(
        selectedDate: Date,
        workMetrics: WorkMetrics,
        summaries: [DailyJournalSummaryRecord],
        repositories: [GitRepositoryRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> CompanionSnapshot {
        let daySnapshot = workMetrics.snapshot(on: selectedDate, calendar: calendar)
        let weekSummary = workMetrics.rangeSummary(scope: .week, containing: selectedDate, calendar: calendar)
        let selectedSummary = matchingSummary(
            for: selectedDate,
            daySnapshot: daySnapshot,
            summaries: summaries,
            calendar: calendar
        )
        let repositoryCounts = repositorySelectionCounts(from: repositories)
        let activeWeekDays = workMetrics
            .dailySnapshots(in: WorkRangeScope.week.interval(containing: selectedDate, calendar: calendar), calendar: calendar)
            .filter { $0.commitCount > 0 }
            .count

        return CompanionSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            primary: CompanionSnapshot.Card(
                title: selectedDateTitle(selectedDate, calendar: calendar),
                value: metricValue(daySnapshot.displayValue, unit: daySnapshot.displayUnit),
                detail: primaryDetail(daySnapshot: daySnapshot, hasSummary: selectedSummary != nil)
            ),
            week: CompanionSnapshot.Card(
                title: "Week",
                value: metricValue(weekSummary.displayValue, unit: weekSummary.displayUnit),
                detail: weekDetail(activeDays: activeWeekDays, commitCount: weekSummary.commitCount)
            ),
            journal: CompanionSnapshot.Card(
                title: "Journal",
                value: journalValue(hasSummary: selectedSummary != nil, commitCount: daySnapshot.commitCount),
                detail: journalDetail(hasSummary: selectedSummary != nil, commitCount: daySnapshot.commitCount)
            ),
            repositories: CompanionSnapshot.Card(
                title: "Repos",
                value: repositoryValue(selected: repositoryCounts.selected, total: repositoryCounts.total),
                detail: "GitHub credentials stay in the main app."
            )
        )
    }

    private static func matchingSummary(
        for selectedDate: Date,
        daySnapshot: DayWorkSnapshot,
        summaries: [DailyJournalSummaryRecord],
        calendar: Calendar
    ) -> DailyJournalSummaryRecord? {
        let dayKey = GitCommitRecord.dayKey(for: selectedDate, calendar: calendar)
        let selectedCommitIDs = Set(daySnapshot.commits.map(\.id))

        guard !selectedCommitIDs.isEmpty else {
            return nil
        }

        return summaries.first { summary in
            guard summary.dayKey == dayKey else {
                return false
            }
            return !Set(summary.sourceCommitIDs).isDisjoint(with: selectedCommitIDs)
        }
    }

    private static func selectedDateTitle(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private static func metricValue(_ value: Int, unit: String) -> String {
        guard value > 0 else {
            return "No work"
        }

        switch unit {
        case "commits":
            return value == 1 ? "1 commit" : "\(value.formatted()) commits"
        case "known changed lines":
            return "\(value.formatted()) known lines"
        case "changed lines":
            return "\(value.formatted()) lines"
        default:
            return "\(value.formatted()) \(unit)"
        }
    }

    private static func primaryDetail(daySnapshot: DayWorkSnapshot, hasSummary: Bool) -> String {
        guard daySnapshot.commitCount > 0 else {
            return "No selected repository work for this day."
        }
        if hasSummary {
            return "Journal summary ready in the main app."
        }
        return "Work captured; generate the journal in the main app."
    }

    private static func weekDetail(activeDays: Int, commitCount: Int) -> String {
        guard commitCount > 0 else {
            return "No selected repository work this week."
        }
        let dayWord = activeDays == 1 ? "day" : "days"
        return "\(activeDays) active \(dayWord) from selected repositories."
    }

    private static func journalValue(hasSummary: Bool, commitCount: Int) -> String {
        if hasSummary {
            return "Ready"
        }
        if commitCount > 0 {
            return "Generate"
        }
        return "No entry"
    }

    private static func journalDetail(hasSummary: Bool, commitCount: Int) -> String {
        if hasSummary {
            return "Review or regenerate on iPhone, iPad, or Mac."
        }
        if commitCount > 0 {
            return "Open the main app to write the private summary."
        }
        return "Journal entries appear after selected work syncs."
    }

    private static func repositorySelectionCounts(from repositories: [GitRepositoryRecord]) -> (selected: Int, total: Int) {
        let githubRepositories = repositories.filter(\.isGitHubBacked)
        let scopedRepositories = githubRepositories.isEmpty ? repositories : githubRepositories
        return (
            selected: scopedRepositories.filter(\.isSelected).count,
            total: scopedRepositories.count
        )
    }

    private static func repositoryValue(selected: Int, total: Int) -> String {
        guard total > 0 else {
            return "No repos"
        }
        return "\(selected) of \(total)"
    }
}
