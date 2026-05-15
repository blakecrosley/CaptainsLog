import Foundation

enum WorkRangeScope: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var lowerTitle: String {
        title.lowercased()
    }

    var pluralTitle: String {
        switch self {
        case .day: "days"
        case .week: "weeks"
        case .month: "months"
        case .year: "years"
        }
    }

    var syncTitle: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    var trendPointCount: Int {
        switch self {
        case .day: 14
        case .week: 10
        case .month: 12
        case .year: 6
        }
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? Self.day.interval(containing: date, calendar: calendar)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? Self.day.interval(containing: date, calendar: calendar)
        case .year:
            return calendar.dateInterval(of: .year, for: date) ?? Self.day.interval(containing: date, calendar: calendar)
        }
    }

    func previousInterval(before interval: DateInterval, calendar: Calendar = .current) -> DateInterval {
        let start: Date
        switch self {
        case .day:
            start = calendar.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
        case .week:
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start) ?? interval.start
        case .month:
            start = calendar.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: interval.start) ?? interval.start
        }
        return DateInterval(start: start, end: interval.start)
    }
}

enum WorkMetricMode: Equatable {
    case diffBacked
    case commitEstimate

    var label: String {
        switch self {
        case .diffBacked: "Diff-backed"
        case .commitEstimate: "Commit estimate"
        }
    }
}

enum WorkDisplayMetric: String, CaseIterable, Identifiable {
    case changes
    case commits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .changes: "Changes"
        case .commits: "Commits"
        }
    }

    var shortUnit: String {
        switch self {
        case .changes: "lines"
        case .commits: "commits"
        }
    }

    func value(for summary: WorkRangeSummary) -> Int {
        switch self {
        case .changes:
            return summary.totalChanges
        case .commits:
            return summary.commitCount
        }
    }

    func trendValue(for summary: WorkRangeSummary) -> Int? {
        switch self {
        case .changes:
            guard summary.isDiffStatsComplete else {
                return nil
            }
            return summary.totalChanges
        case .commits:
            return summary.commitCount
        }
    }

    func value(for snapshot: DayWorkSnapshot) -> Int {
        switch self {
        case .changes:
            return snapshot.totalChanges
        case .commits:
            return snapshot.commitCount
        }
    }

    func heatmapValue(for snapshot: DayWorkSnapshot) -> Int {
        switch self {
        case .changes:
            if snapshot.totalChanges > 0 {
                return snapshot.totalChanges
            }
            return snapshot.commitCount
        case .commits:
            return snapshot.commitCount
        }
    }

    func unit(for summary: WorkRangeSummary) -> String {
        switch self {
        case .changes:
            guard summary.statsBackedCommitCount > 0 else {
                return "changed lines"
            }
            return summary.isDiffStatsComplete ? "changed lines" : "known changed lines"
        case .commits:
            return summary.commitCount == 1 ? "commit" : "commits"
        }
    }

    func averagePerDay(for summary: WorkRangeSummary) -> Double {
        guard summary.dayCount > 0 else {
            return 0
        }
        return Double(value(for: summary)) / Double(summary.dayCount)
    }

    func canCompare(_ current: WorkRangeSummary, _ baseline: WorkRangeSummary) -> Bool {
        switch self {
        case .changes:
            return current.isDiffStatsComplete && baseline.isDiffStatsComplete
        case .commits:
            return true
        }
    }
}

enum WorkTrendDirection: Equatable {
    case up
    case steady
    case down
    case noBaseline

    var label: String {
        switch self {
        case .up: "Trending up"
        case .steady: "Steady"
        case .down: "Trending down"
        case .noBaseline: "Building baseline"
        }
    }

    var symbolName: String {
        switch self {
        case .up: "arrow.up.right"
        case .steady: "arrow.right"
        case .down: "arrow.down.right"
        case .noBaseline: "chart.line.uptrend.xyaxis"
        }
    }
}

struct DayWorkSnapshot {
    let date: Date
    let commits: [GitCommitRecord]
    let commitCount: Int
    let statsBackedCommitCount: Int
    let additions: Int
    let deletions: Int
    let totalChanges: Int
    let changedFiles: Int
    let workUnits: Int
    let categoryWeights: [WorkCategory: Int]
    let languageWeights: [String: Int]
    let repositoryWeights: [String: Int]

    var coverage: Double {
        guard commitCount > 0 else { return 1 }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }

    var hasDiffStats: Bool {
        statsBackedCommitCount > 0
    }

    var missingDiffStatsCount: Int {
        max(commitCount - statsBackedCommitCount, 0)
    }

    var mode: WorkMetricMode {
        isDiffStatsComplete ? .diffBacked : .commitEstimate
    }

    var displayValue: Int {
        hasDiffStats ? totalChanges : commitCount
    }

    var displayUnit: String {
        if !hasDiffStats {
            return "commits"
        }
        return isDiffStatsComplete ? "changed lines" : "known changed lines"
    }

    var isDiffStatsComplete: Bool {
        missingDiffStatsCount == 0
    }
}

struct WorkRangeSummary {
    let start: Date
    let end: Date
    let dayCount: Int
    let commitCount: Int
    let statsBackedCommitCount: Int
    let additions: Int
    let deletions: Int
    let totalChanges: Int
    let changedFiles: Int
    let workUnits: Int
    let categoryWeights: [WorkCategory: Int]
    let languageWeights: [String: Int]
    let repositoryWeights: [String: Int]

    var coverage: Double {
        guard commitCount > 0 else { return 1 }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }

    var hasDiffStats: Bool {
        statsBackedCommitCount > 0
    }

    var missingDiffStatsCount: Int {
        max(commitCount - statsBackedCommitCount, 0)
    }

    var mode: WorkMetricMode {
        isDiffStatsComplete ? .diffBacked : .commitEstimate
    }

    var displayValue: Int {
        hasDiffStats ? totalChanges : commitCount
    }

    var displayUnit: String {
        if !hasDiffStats {
            return "commits"
        }
        return isDiffStatsComplete ? "changed lines" : "known changed lines"
    }

    var averagePerDay: Double {
        guard dayCount > 0 else { return 0 }
        return Double(displayValue) / Double(dayCount)
    }

    var isDiffStatsComplete: Bool {
        missingDiffStatsCount == 0
    }
}

struct WorkTrendSummary {
    let scope: WorkRangeScope
    let current: WorkRangeSummary
    let baseline: WorkRangeSummary

    var percentChange: Double? {
        guard current.hasDiffStats == baseline.hasDiffStats, baseline.averagePerDay > 0 else {
            return nil
        }
        return (current.averagePerDay - baseline.averagePerDay) / baseline.averagePerDay
    }

    var direction: WorkTrendDirection {
        guard let percentChange else {
            return .noBaseline
        }
        if percentChange > 0.10 {
            return .up
        }
        if percentChange < -0.10 {
            return .down
        }
        return .steady
    }
}

struct WorkMapDayInsight {
    let snapshot: DayWorkSnapshot

    var commitCount: Int {
        snapshot.commitCount
    }

    var repositoryCount: Int {
        Set(snapshot.commits.map(\.repositoryFullName)).count
    }

    var topRepository: String? {
        snapshot.repositoryWeights.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    var topCategory: WorkCategory? {
        snapshot.categoryWeights.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    var topLanguage: String? {
        snapshot.languageWeights.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    var activeSpanMinutes: Int? {
        guard snapshot.commits.count > 1 else {
            return nil
        }
        let dates = snapshot.commits.map(\.authoredAt)
        guard let first = dates.min(), let last = dates.max() else {
            return nil
        }
        let minutes = Int(last.timeIntervalSince(first) / 60)
        return minutes > 0 ? minutes : nil
    }

    var commitSample: [GitCommitRecord] {
        Array(snapshot.commits.prefix(3))
    }
}

struct WorkMapPeriodInsights {
    let scope: WorkRangeScope
    let metric: WorkDisplayMetric
    let summary: WorkRangeSummary
    let snapshots: [DayWorkSnapshot]
    let selectedDate: Date
    let activeDayCount: Int
    let currentStreak: Int
    let longestStreak: Int
    let busiestDay: DayWorkSnapshot?
    let medianActiveDayValue: Int
    let topDayShare: Double
    let mostActiveWeekday: Int?
    let firstActiveDate: Date?
    let lastActiveDate: Date?

    var repositoryCount: Int {
        summary.repositoryWeights.count
    }

    var topRepository: (name: String, value: Int, share: Double)? {
        topItem(in: summary.repositoryWeights)
    }

    var topCategory: (category: WorkCategory, value: Int, share: Double)? {
        topItem(in: summary.categoryWeights).map { (category: $0.name, value: $0.value, share: $0.share) }
    }

    var topLanguage: (name: String, value: Int, share: Double)? {
        topItem(in: summary.languageWeights)
    }

    var languageBasisLabel: String {
        "files touched"
    }

    var hasWork: Bool {
        summary.commitCount > 0
    }

    func value(for snapshot: DayWorkSnapshot) -> Int {
        metric.value(for: snapshot)
    }

    private func topItem<Key: Hashable>(in weights: [Key: Int]) -> (name: Key, value: Int, share: Double)? {
        guard let item = weights.max(by: { $0.value < $1.value }), item.value > 0 else {
            return nil
        }
        let total = max(weights.reduce(0) { $0 + $1.value }, 1)
        return (item.key, item.value, Double(item.value) / Double(total))
    }
}

struct WorkMetrics {
    private static let maxWorkUnitsPerCommit = 2_000

    let commitsByDay: [String: [GitCommitRecord]]
    private let snapshotsByDay: [String: DayWorkSnapshot]
    private let oldestCommit: Date?

    init(commits: [GitCommitRecord]) {
        let grouped = Dictionary(grouping: commits, by: \.dayKey)
        self.commitsByDay = grouped
        self.snapshotsByDay = grouped.mapValues { commits in
            let sorted = commits.sorted { $0.authoredAt > $1.authoredAt }
            let date = sorted.first.map { Calendar.current.startOfDay(for: $0.authoredAt) } ?? Date()
            return Self.snapshot(date: date, commits: sorted)
        }
        self.oldestCommit = commits.map(\.authoredAt).min()
    }

    var oldestCommitDate: Date? {
        oldestCommit
    }

    func snapshot(on date: Date, calendar: Calendar = .current) -> DayWorkSnapshot {
        let dayKey = GitCommitRecord.dayKey(for: date, calendar: calendar)
        return snapshotsByDay[dayKey] ?? Self.emptySnapshot(on: date, calendar: calendar)
    }

    func commitCount(on date: Date, calendar: Calendar = .current) -> Int {
        snapshot(on: date, calendar: calendar).commitCount
    }

    func commits(on date: Date, calendar: Calendar = .current) -> [GitCommitRecord] {
        let dayKey = GitCommitRecord.dayKey(for: date, calendar: calendar)
        return snapshotsByDay[dayKey]?.commits ?? []
    }

    func rangeSummary(scope: WorkRangeScope, containing date: Date, calendar: Calendar = .current) -> WorkRangeSummary {
        let interval = scope.interval(containing: date, calendar: calendar)
        return rangeSummary(interval: interval, calendar: calendar)
    }

    func trend(scope: WorkRangeScope, containing date: Date, calendar: Calendar = .current) -> WorkTrendSummary {
        let currentInterval = scope.interval(containing: date, calendar: calendar)
        let current = rangeSummary(interval: currentInterval, calendar: calendar)
        let baseline = rangeSummary(interval: scope.previousInterval(before: currentInterval, calendar: calendar), calendar: calendar)
        return WorkTrendSummary(scope: scope, current: current, baseline: baseline)
    }

    func workMapDayInsight(on date: Date, calendar: Calendar = .current) -> WorkMapDayInsight {
        WorkMapDayInsight(snapshot: snapshot(on: date, calendar: calendar))
    }

    func workMapPeriodInsights(
        scope: WorkRangeScope,
        containing date: Date,
        metric: WorkDisplayMetric,
        calendar: Calendar = .current
    ) -> WorkMapPeriodInsights {
        let interval = scope.interval(containing: date, calendar: calendar)
        return workMapPeriodInsights(
            interval: interval,
            selectedDate: date,
            metric: metric,
            scope: scope,
            calendar: calendar
        )
    }

    func workMapPeriodInsights(
        interval: DateInterval,
        selectedDate: Date,
        metric: WorkDisplayMetric,
        scope: WorkRangeScope = .year,
        calendar: Calendar = .current
    ) -> WorkMapPeriodInsights {
        let snapshots = dailySnapshots(in: interval, calendar: calendar)
        let activeSnapshots = snapshots.filter { metric.value(for: $0) > 0 || $0.commitCount > 0 }
        let metricValues = activeSnapshots
            .map { metric.value(for: $0) }
            .filter { $0 > 0 }
            .sorted()
        let busiestDay = activeSnapshots.max { lhs, rhs in
            metric.heatmapValue(for: lhs) < metric.heatmapValue(for: rhs)
        }
        let totalMetricValue = max(activeSnapshots.reduce(0) { $0 + max(metric.value(for: $1), 0) }, 0)
        let busiestValue = busiestDay.map { max(metric.value(for: $0), 0) } ?? 0

        return WorkMapPeriodInsights(
            scope: scope,
            metric: metric,
            summary: rangeSummary(interval: interval, calendar: calendar),
            snapshots: snapshots,
            selectedDate: calendar.startOfDay(for: selectedDate),
            activeDayCount: activeSnapshots.count,
            currentStreak: currentStreak(in: snapshots, selectedDate: selectedDate, calendar: calendar),
            longestStreak: longestStreak(in: snapshots),
            busiestDay: busiestDay,
            medianActiveDayValue: medianValue(in: metricValues),
            topDayShare: totalMetricValue > 0 ? Double(busiestValue) / Double(totalMetricValue) : 0,
            mostActiveWeekday: mostActiveWeekday(in: activeSnapshots, metric: metric, calendar: calendar),
            firstActiveDate: activeSnapshots.map(\.date).min(),
            lastActiveDate: activeSnapshots.map(\.date).max()
        )
    }

    func rangeSummary(interval: DateInterval, calendar: Calendar = .current) -> WorkRangeSummary {
        let snapshots = dailySnapshots(in: interval, calendar: calendar)

        return WorkRangeSummary(
            start: interval.start,
            end: interval.end,
            dayCount: max(snapshots.count, 1),
            commitCount: snapshots.reduce(0) { $0 + $1.commitCount },
            statsBackedCommitCount: snapshots.reduce(0) { $0 + $1.statsBackedCommitCount },
            additions: snapshots.reduce(0) { $0 + $1.additions },
            deletions: snapshots.reduce(0) { $0 + $1.deletions },
            totalChanges: snapshots.reduce(0) { $0 + $1.totalChanges },
            changedFiles: snapshots.reduce(0) { $0 + $1.changedFiles },
            workUnits: snapshots.reduce(0) { $0 + $1.workUnits },
            categoryWeights: mergedWeights(snapshots.map(\.categoryWeights)),
            languageWeights: mergedWeights(snapshots.map(\.languageWeights)),
            repositoryWeights: mergedWeights(snapshots.map(\.repositoryWeights))
        )
    }

    func dailySnapshots(in interval: DateInterval, calendar: Calendar = .current) -> [DayWorkSnapshot] {
        days(in: interval, calendar: calendar).map { snapshot(on: $0, calendar: calendar) }
    }

    private static func snapshot(date: Date, commits: [GitCommitRecord]) -> DayWorkSnapshot {
        var additions = 0
        var deletions = 0
        var totalChanges = 0
        var changedFiles = 0
        var workUnits = 0
        var statsBacked = 0
        var categoryWeights: [WorkCategory: Int] = [:]
        var languageWeights: [String: Int] = [:]
        var repositoryWeights: [String: Int] = [:]

        for commit in commits {
            let hasStats = commit.hasDiffStats
            let weight = weight(for: commit)
            if hasStats {
                statsBacked += 1
                additions += commit.additions ?? 0
                deletions += commit.deletions ?? 0
                totalChanges += commit.totalChanges ?? ((commit.additions ?? 0) + (commit.deletions ?? 0))
                changedFiles += commit.changedFileCount ?? 0
                workUnits += weight
            }

            categoryWeights[WorkClassifier.category(for: commit), default: 0] += weight
            for language in commit.changedFiles.map(WorkLanguageClassifier.language(for:)) {
                languageWeights[language, default: 0] += 1
            }
            repositoryWeights[commit.repositoryFullName, default: 0] += weight
        }

        return DayWorkSnapshot(
            date: date,
            commits: commits,
            commitCount: commits.count,
            statsBackedCommitCount: statsBacked,
            additions: additions,
            deletions: deletions,
            totalChanges: totalChanges,
            changedFiles: changedFiles,
            workUnits: workUnits,
            categoryWeights: categoryWeights,
            languageWeights: languageWeights,
            repositoryWeights: repositoryWeights
        )
    }

    private static func emptySnapshot(on date: Date, calendar: Calendar) -> DayWorkSnapshot {
        DayWorkSnapshot(
            date: calendar.startOfDay(for: date),
            commits: [],
            commitCount: 0,
            statsBackedCommitCount: 0,
            additions: 0,
            deletions: 0,
            totalChanges: 0,
            changedFiles: 0,
            workUnits: 0,
            categoryWeights: [:],
            languageWeights: [:],
            repositoryWeights: [:]
        )
    }

    private static func weight(for commit: GitCommitRecord) -> Int {
        guard commit.hasDiffStats else {
            return 1
        }
        let total = commit.totalChanges ?? ((commit.additions ?? 0) + (commit.deletions ?? 0))
        return max(1, min(total, maxWorkUnitsPerCommit))
    }

    private func currentStreak(in snapshots: [DayWorkSnapshot], selectedDate: Date, calendar: Calendar) -> Int {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let eligibleSnapshots = snapshots
            .filter { $0.date <= selectedDay }
            .sorted { $0.date > $1.date }
        var streak = 0

        for snapshot in eligibleSnapshots {
            guard snapshot.commitCount > 0 else {
                break
            }
            streak += 1
        }
        return streak
    }

    private func longestStreak(in snapshots: [DayWorkSnapshot]) -> Int {
        var longest = 0
        var current = 0

        for snapshot in snapshots.sorted(by: { $0.date < $1.date }) {
            if snapshot.commitCount > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return longest
    }

    private func medianValue(in sortedValues: [Int]) -> Int {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }

    private func mostActiveWeekday(
        in snapshots: [DayWorkSnapshot],
        metric: WorkDisplayMetric,
        calendar: Calendar
    ) -> Int? {
        var values: [Int: Int] = [:]

        for snapshot in snapshots {
            let weekday = calendar.component(.weekday, from: snapshot.date)
            values[weekday, default: 0] += max(metric.heatmapValue(for: snapshot), 0)
        }

        return values.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    private func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var current = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        var result: [Date] = []

        while current <= end {
            result.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return result
    }

    private func mergedWeights<Key: Hashable>(_ maps: [[Key: Int]]) -> [Key: Int] {
        maps.reduce(into: [:]) { partial, map in
            for (key, value) in map {
                partial[key, default: 0] += value
            }
        }
    }
}
