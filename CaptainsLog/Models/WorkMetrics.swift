import Foundation

enum WorkRangeScope: String, CaseIterable, Identifiable {
    case day
    case week
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .quarter: "Quarter"
        case .year: "Year"
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
        case .quarter:
            let components = calendar.dateComponents([.year, .month], from: date)
            let month = components.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1))
                ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
            return DateInterval(start: start, end: end)
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
        case .quarter:
            start = calendar.date(byAdding: .month, value: -3, to: interval.start) ?? interval.start
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
    let repositoryWeights: [String: Int]

    var coverage: Double {
        guard commitCount > 0 else { return 1 }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }

    var mode: WorkMetricMode {
        coverage >= WorkMetrics.diffCoverageThreshold ? .diffBacked : .commitEstimate
    }

    var displayValue: Int {
        mode == .diffBacked ? workUnits : commitCount
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
    let repositoryWeights: [String: Int]

    var coverage: Double {
        guard commitCount > 0 else { return 1 }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }

    var mode: WorkMetricMode {
        coverage >= WorkMetrics.diffCoverageThreshold ? .diffBacked : .commitEstimate
    }

    var displayValue: Int {
        mode == .diffBacked ? workUnits : commitCount
    }

    var displayUnit: String {
        mode == .diffBacked ? "work units" : "commits"
    }

    var averagePerDay: Double {
        guard dayCount > 0 else { return 0 }
        return Double(displayValue) / Double(dayCount)
    }
}

struct WorkTrendSummary {
    let scope: WorkRangeScope
    let current: WorkRangeSummary
    let baseline: WorkRangeSummary

    var percentChange: Double? {
        guard baseline.averagePerDay > 0 else {
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

struct WorkMetrics {
    static let diffCoverageThreshold = 0.60
    private static let maxWorkUnitsPerCommit = 2_000

    let commitsByDay: [String: [GitCommitRecord]]

    init(commits: [GitCommitRecord]) {
        self.commitsByDay = Dictionary(grouping: commits, by: \.dayKey)
    }

    func snapshot(on date: Date, calendar: Calendar = .current) -> DayWorkSnapshot {
        let dayKey = GitCommitRecord.dayKey(for: date, calendar: calendar)
        let commits = (commitsByDay[dayKey] ?? []).sorted { $0.authoredAt > $1.authoredAt }
        return snapshot(date: calendar.startOfDay(for: date), commits: commits)
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

    private func rangeSummary(interval: DateInterval, calendar: Calendar) -> WorkRangeSummary {
        let days = days(in: interval, calendar: calendar)
        let snapshots = days.map { snapshot(on: $0, calendar: calendar) }

        return WorkRangeSummary(
            start: interval.start,
            end: interval.end,
            dayCount: max(days.count, 1),
            commitCount: snapshots.reduce(0) { $0 + $1.commitCount },
            statsBackedCommitCount: snapshots.reduce(0) { $0 + $1.statsBackedCommitCount },
            additions: snapshots.reduce(0) { $0 + $1.additions },
            deletions: snapshots.reduce(0) { $0 + $1.deletions },
            totalChanges: snapshots.reduce(0) { $0 + $1.totalChanges },
            changedFiles: snapshots.reduce(0) { $0 + $1.changedFiles },
            workUnits: snapshots.reduce(0) { $0 + $1.workUnits },
            categoryWeights: mergedWeights(snapshots.map(\.categoryWeights)),
            repositoryWeights: mergedWeights(snapshots.map(\.repositoryWeights))
        )
    }

    private func snapshot(date: Date, commits: [GitCommitRecord]) -> DayWorkSnapshot {
        var additions = 0
        var deletions = 0
        var totalChanges = 0
        var changedFiles = 0
        var workUnits = 0
        var statsBacked = 0
        var categoryWeights: [WorkCategory: Int] = [:]
        var repositoryWeights: [String: Int] = [:]

        for commit in commits {
            let hasStats = commit.hasDiffStats
            let weight = Self.weight(for: commit)
            if hasStats {
                statsBacked += 1
                additions += commit.additions ?? 0
                deletions += commit.deletions ?? 0
                totalChanges += commit.totalChanges ?? ((commit.additions ?? 0) + (commit.deletions ?? 0))
                changedFiles += commit.changedFileCount ?? 0
                workUnits += weight
            }

            categoryWeights[WorkClassifier.category(for: commit), default: 0] += weight
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
            repositoryWeights: repositoryWeights
        )
    }

    private static func weight(for commit: GitCommitRecord) -> Int {
        guard commit.hasDiffStats else {
            return 1
        }
        let total = commit.totalChanges ?? ((commit.additions ?? 0) + (commit.deletions ?? 0))
        return max(1, min(total, maxWorkUnitsPerCommit))
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
