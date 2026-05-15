import XCTest
@testable import Captain_s_Log

final class CalendarMathTests: XCTestCase {
    func testMonthGridPadsToWholeWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))

        let days = CalendarMath.monthGridDays(for: date, calendar: calendar)

        XCTAssertEqual(days.count % 7, 0)
        XCTAssertEqual(days.compactMap { $0 }.count, 31)
    }

    func testContributionWeeksReturnsSevenDayColumns() throws {
        let end = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 10)))

        let weeks = CalendarMath.contributionWeeks(ending: end, weekCount: 12)

        XCTAssertEqual(weeks.count, 12)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }

    func testContributionWeeksAreOldestToNewest() throws {
        let calendar = Calendar(identifier: .gregorian)
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))

        let weeks = CalendarMath.contributionWeeks(ending: end, weekCount: 2, calendar: calendar)

        let firstWeekStart = try XCTUnwrap(weeks.first?.first)
        let lastWeekStart = try XCTUnwrap(weeks.last?.first)
        XCTAssertLessThan(firstWeekStart, lastWeekStart)
        XCTAssertTrue(calendar.isDate(end, equalTo: lastWeekStart, toGranularity: .weekOfYear))
    }

    func testContributionWeeksCanSpanImportedHistory() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 2)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))

        let weeks = CalendarMath.contributionWeeks(from: start, through: end, calendar: calendar)

        XCTAssertGreaterThan(weeks.count, 100)
        XCTAssertTrue(calendar.isDate(start, equalTo: try XCTUnwrap(weeks.first?.first), toGranularity: .weekOfYear))
        XCTAssertTrue(calendar.isDate(end, equalTo: try XCTUnwrap(weeks.last?.first), toGranularity: .weekOfYear))
    }

    func testContributionWeeksForCalendarYearStaysBounded() throws {
        let calendar = Calendar(identifier: .gregorian)

        let weeks = CalendarMath.contributionWeeks(inYear: 2026, calendar: calendar)

        XCTAssertTrue((52...54).contains(weeks.count))
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertTrue(calendar.isDate(
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))),
            equalTo: try XCTUnwrap(weeks.first?.first),
            toGranularity: .weekOfYear
        ))
        XCTAssertTrue(calendar.isDate(
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))),
            equalTo: try XCTUnwrap(weeks.last?.first),
            toGranularity: .weekOfYear
        ))
    }

    func testContributionMonthStartOnlyMarksFirstDayOfMonthColumns() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let firstMayWeek = CalendarMath.weekDays(
            containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))),
            calendar: calendar
        )
        let secondMayWeek = CalendarMath.weekDays(
            containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))),
            calendar: calendar
        )

        let marker = try XCTUnwrap(CalendarMath.contributionMonthStart(in: firstMayWeek, calendar: calendar))

        XCTAssertEqual(calendar.component(.month, from: marker), 5)
        XCTAssertEqual(calendar.component(.day, from: marker), 1)
        XCTAssertNil(CalendarMath.contributionMonthStart(in: secondMayWeek, calendar: calendar))
    }

    func testContributionMonthStartIgnoresOutOfRangeYearEdges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let interval = DateInterval(start: start, end: end)
        let firstWeek = CalendarMath.weekDays(containing: start, calendar: calendar)
        let lastWeek = CalendarMath.weekDays(
            containing: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))),
            calendar: calendar
        )

        XCTAssertNotNil(CalendarMath.contributionMonthStart(in: firstWeek, activeInterval: interval, calendar: calendar))
        XCTAssertNil(CalendarMath.contributionMonthStart(in: lastWeek, activeInterval: interval, calendar: calendar))
    }

    func testActivityDensityScaleKeepsBusyDaysVisuallyDistinct() {
        let scale = ActivityDensityScale(counts: [0, 6, 10, 20, 40, 80, 160])

        XCTAssertEqual(scale.level(for: 0), 0)
        XCTAssertGreaterThan(scale.level(for: 6), 0)
        XCTAssertEqual(scale.level(for: 160), 4)
        XCTAssertGreaterThan(
            Set([6, 10, 20, 40, 80, 160].map { scale.level(for: $0) }).count,
            1
        )
    }

    func testActivityDensityScaleDoesNotLetOneHugeDayFlattenTheMap() {
        let scale = ActivityDensityScale(counts: [0, 18, 24, 36, 52, 90, 30_000])

        XCTAssertEqual(scale.level(for: 30_000), 4)
        XCTAssertGreaterThan(scale.level(for: 90), scale.level(for: 18))
        XCTAssertGreaterThan(
            Set([18, 24, 36, 52, 90, 30_000].map { scale.level(for: $0) }).count,
            2
        )
    }

    func testActivityDataTrustMarksFutureDays() throws {
        let calendar = utcCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16)))
        let repository = makeRepository(fullName: "blakecrosley/captains-log", isSelected: true)
        repository.lastSyncedAt = today

        XCTAssertEqual(
            ActivityDataTrust.state(for: tomorrow, repositories: [repository], now: today, calendar: calendar),
            .future
        )
    }

    func testActivityDataTrustUsesRecentHotSyncWindow() throws {
        let calendar = utcCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let coveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let uncoveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        let repository = makeRepository(fullName: "blakecrosley/captains-log", isSelected: true)
        repository.lastSyncedAt = today

        XCTAssertEqual(
            ActivityDataTrust.state(for: coveredDay, repositories: [repository], now: today, calendar: calendar),
            .verified
        )
        XCTAssertEqual(
            ActivityDataTrust.state(for: uncoveredDay, repositories: [repository], now: today, calendar: calendar),
            .unknown
        )
    }

    func testActivityDataTrustUsesHistoryCursor() throws {
        let calendar = utcCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let coveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let uncoveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
        let repository = makeRepository(fullName: "blakecrosley/reps", isSelected: true)
        repository.historyBackfillCursorDate = coveredDay

        XCTAssertEqual(
            ActivityDataTrust.state(for: coveredDay, repositories: [repository], now: today, calendar: calendar),
            .verified
        )
        XCTAssertEqual(
            ActivityDataTrust.state(for: uncoveredDay, repositories: [repository], now: today, calendar: calendar),
            .unknown
        )
    }

    func testActivityDataTrustTreatsActiveHistoryMonthAsUnverified() throws {
        let calendar = utcCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let activeMonthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let activeMonthEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let coveredLaterDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let activeMonthDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let repository = makeRepository(fullName: "blakecrosley/reps", isSelected: true)
        repository.markHistoryBackfillMonth(DateInterval(start: activeMonthStart, end: activeMonthEnd))

        XCTAssertEqual(
            ActivityDataTrust.state(for: coveredLaterDay, repositories: [repository], now: today, calendar: calendar),
            .verified
        )
        XCTAssertEqual(
            ActivityDataTrust.state(for: activeMonthDay, repositories: [repository], now: today, calendar: calendar),
            .unknown
        )
    }

    func testActivityDataTrustUsesCompletedHistoryLowerBound() throws {
        let calendar = utcCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let lowerBound = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let coveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let uncoveredDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31)))
        let repository = makeRepository(fullName: "blakecrosley/reps", isSelected: true)
        repository.prepareHistoryBackfill(lowerBound: lowerBound)
        repository.advanceHistoryBackfillCursor(to: lowerBound, completedAt: today)

        XCTAssertEqual(
            ActivityDataTrust.state(for: coveredDay, repositories: [repository], now: today, calendar: calendar),
            .verified
        )
        XCTAssertEqual(
            ActivityDataTrust.state(for: uncoveredDay, repositories: [repository], now: today, calendar: calendar),
            .unknown
        )
    }

    func testWorkRangeScopeUsesDateAnchoredLabels() {
        XCTAssertEqual(WorkRangeScope.allCases.map(\.title), ["Day", "Week", "Month", "Year"])
    }

    func testWorkRangeScopeYearContainsSelectedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))

        let interval = WorkRangeScope.year.interval(containing: selectedDate, calendar: calendar)

        XCTAssertEqual(interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))))
        XCTAssertEqual(interval.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))))
    }

    func testWorkTrendUsesPreviousMatchingRangeAsBaseline() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))

        let trend = WorkMetrics(commits: []).trend(scope: .month, containing: selectedDate, calendar: calendar)

        XCTAssertEqual(trend.current.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))))
        XCTAssertEqual(trend.baseline.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))))
        XCTAssertEqual(trend.baseline.end, trend.current.start)
    }

    func testWorkMetricsUsesCommitEstimateWhenStatsAreSparse() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commits = [
            makeCommit(sha: "aaaaaaa111111111111111111111111111111111", date: date, message: "Add overview"),
            makeCommit(sha: "bbbbbbb111111111111111111111111111111111", date: date, message: "Fix sync")
        ]
        commits[0].additions = 90
        commits[0].deletions = 10
        commits[0].totalChanges = 100
        commits[0].changedFileCount = 3
        commits[0].diffStatsFetchedAt = date

        let snapshot = WorkMetrics(commits: commits).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(snapshot.commitCount, 2)
        XCTAssertEqual(snapshot.statsBackedCommitCount, 1)
        XCTAssertEqual(snapshot.mode, .commitEstimate)
        XCTAssertEqual(snapshot.displayValue, 100)
        XCTAssertEqual(snapshot.displayUnit, "known changed lines")
    }

    func testWorkRangeSummaryReportsMissingDiffStats() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commits = [
            makeCommit(sha: "aaaabbb111111111111111111111111111111111", date: date, message: "Known stats"),
            makeCommit(sha: "aaaaccc111111111111111111111111111111111", date: date, message: "Missing stats")
        ]
        commits[0].additions = 24
        commits[0].deletions = 6
        commits[0].totalChanges = 30
        commits[0].changedFileCount = 2
        commits[0].diffStatsFetchedAt = date

        let summary = WorkMetrics(commits: commits).rangeSummary(scope: .week, containing: date, calendar: calendar)

        XCTAssertEqual(summary.commitCount, 2)
        XCTAssertEqual(summary.statsBackedCommitCount, 1)
        XCTAssertEqual(summary.missingDiffStatsCount, 1)
    }

    func testChangesHeatmapPreservesCommitActivityWhenStatsAreMissing() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commits = [
            makeCommit(sha: "1111111111111111111111111111111111111111", date: date, message: "Add importer"),
            makeCommit(sha: "2222222222222222222222222222222222222222", date: date, message: "Fix importer")
        ]

        let snapshot = WorkMetrics(commits: commits).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(WorkDisplayMetric.changes.value(for: snapshot), 0)
        XCTAssertEqual(WorkDisplayMetric.changes.heatmapValue(for: snapshot), 2)
    }

    func testChangesTrendDoesNotPlotMissingLineStatsAsZero() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commits = [
            makeCommit(sha: "1111111222222222222222222222222222222222", date: date, message: "Missing stats")
        ]

        let summary = WorkMetrics(commits: commits).rangeSummary(scope: .week, containing: date, calendar: calendar)

        XCTAssertEqual(summary.commitCount, 1)
        XCTAssertNil(WorkDisplayMetric.changes.trendValue(for: summary))
        XCTAssertEqual(WorkDisplayMetric.commits.trendValue(for: summary), 1)
    }

    func testChangesHeatmapUsesKnownLineChangesWhenAvailable() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commit = makeCommit(
            sha: "3333333333333333333333333333333333333333",
            date: date,
            message: "Add diff stats"
        )
        commit.additions = 31
        commit.deletions = 11
        commit.totalChanges = 42
        commit.changedFileCount = 3

        let snapshot = WorkMetrics(commits: [commit]).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(WorkDisplayMetric.changes.heatmapValue(for: snapshot), 42)
    }

    func testChangesTrendPlotsKnownLineStats() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commit = makeCommit(
            sha: "3333333444444444444444444444444444444444",
            date: date,
            message: "Known stats"
        )
        commit.additions = 31
        commit.deletions = 11
        commit.totalChanges = 42
        commit.changedFileCount = 3
        commit.diffStatsFetchedAt = date

        let summary = WorkMetrics(commits: [commit]).rangeSummary(scope: .week, containing: date, calendar: calendar)

        XCTAssertEqual(WorkDisplayMetric.changes.trendValue(for: summary), 42)
    }

    func testChangesTrendRequiresCompleteLineStatsCoverage() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let known = makeCommit(
            sha: "3333333555555555555555555555555555555555",
            date: date,
            message: "Known stats"
        )
        known.additions = 31
        known.deletions = 11
        known.totalChanges = 42
        known.changedFileCount = 3
        known.diffStatsFetchedAt = date
        let missing = makeCommit(
            sha: "3333333666666666666666666666666666666666",
            date: date,
            message: "Missing stats"
        )

        let summary = WorkMetrics(commits: [known, missing]).rangeSummary(scope: .week, containing: date, calendar: calendar)

        XCTAssertEqual(summary.totalChanges, 42)
        XCTAssertEqual(summary.missingDiffStatsCount, 1)
        XCTAssertEqual(WorkDisplayMetric.changes.unit(for: summary), "known changed lines")
        XCTAssertNil(WorkDisplayMetric.changes.trendValue(for: summary))
    }

    func testWorkMetricsUsesDiffBackedWorkUnitsAtCoverageThreshold() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commits = [
            makeCommit(sha: "ccccccc111111111111111111111111111111111", date: date, message: "Add work metrics"),
            makeCommit(sha: "ddddddd111111111111111111111111111111111", date: date, message: "Add tests")
        ]
        for commit in commits {
            commit.additions = 20
            commit.deletions = 5
            commit.totalChanges = 25
            commit.changedFileCount = 2
            commit.changedFiles = ["Sources/App.swift", "Tests/AppTests.swift"]
            commit.diffStatsFetchedAt = date
        }

        let snapshot = WorkMetrics(commits: commits).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(snapshot.mode, .diffBacked)
        XCTAssertEqual(snapshot.workUnits, 50)
        XCTAssertEqual(snapshot.displayValue, 50)
        XCTAssertEqual(snapshot.displayUnit, "changed lines")
        XCTAssertEqual(snapshot.languageWeights["Swift"], 4)
    }

    func testWorkMetricsDisplaysRawChangedLinesForLargeSingleCommit() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commit = makeCommit(
            sha: "eeeeeee111111111111111111111111111111111",
            date: date,
            message: "Initial import"
        )
        commit.additions = 5_500
        commit.deletions = 500
        commit.totalChanges = 6_000
        commit.changedFileCount = 48
        commit.diffStatsFetchedAt = date

        let snapshot = WorkMetrics(commits: [commit]).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(snapshot.workUnits, 2_000)
        XCTAssertEqual(snapshot.displayValue, 6_000)
        XCTAssertEqual(snapshot.displayUnit, "changed lines")
    }

    func testWorkMapDayInsightDerivesSelectedDayFacts() throws {
        let calendar = Calendar(identifier: .gregorian)
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9)))
        let lateMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 11, minute: 30)))
        let first = makeCommit(
            sha: "eeeeeee333333333333333333333333333333333",
            date: morning,
            message: "Add work map tests"
        )
        first.additions = 90
        first.deletions = 10
        first.totalChanges = 100
        first.changedFileCount = 2
        first.changedFiles = ["Tests/WorkMapTests.swift", "Tests/Fixtures.swift"]
        first.diffStatsFetchedAt = morning
        let second = makeCommit(
            sha: "eeeeeee444444444444444444444444444444444",
            date: lateMorning,
            message: "Document work map"
        )
        second.additions = 5
        second.deletions = 1
        second.totalChanges = 6
        second.changedFileCount = 1
        second.changedFiles = ["README.md"]
        second.diffStatsFetchedAt = lateMorning

        let insight = WorkMetrics(commits: [first, second]).workMapDayInsight(on: morning, calendar: calendar)

        XCTAssertEqual(insight.commitCount, 2)
        XCTAssertEqual(insight.repositoryCount, 1)
        XCTAssertEqual(insight.topRepository, "blakecrosley/captains-log")
        XCTAssertEqual(insight.topCategory, .tests)
        XCTAssertEqual(insight.activeSpanMinutes, 150)
        XCTAssertEqual(insight.commitSample.map(\.shortSHA), [second.shortSHA, first.shortSHA])
    }

    func testWorkMapPeriodInsightsSummarizeRhythmLoadAndFocus() throws {
        let calendar = Calendar(identifier: .gregorian)
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let wednesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let commits = [
            makeCommit(sha: "eeeeeee555555555555555555555555555555555", repositoryFullName: "blakecrosley/reps", date: monday, message: "Monday"),
            makeCommit(sha: "eeeeeee666666666666666666666666666666666", repositoryFullName: "blakecrosley/reps", date: tuesday, message: "Tuesday"),
            makeCommit(sha: "eeeeeee777777777777777777777777777777777", repositoryFullName: "blakecrosley/reps", date: wednesday, message: "Wednesday"),
            makeCommit(sha: "eeeeeee888888888888888888888888888888888", repositoryFullName: "blakecrosley/site", date: friday, message: "Friday")
        ]
        let totals = [20, 30, 100, 10]
        for (commit, total) in zip(commits, totals) {
            commit.additions = total
            commit.deletions = 0
            commit.totalChanges = total
            commit.changedFileCount = 1
            commit.changedFiles = ["Sources/App.swift"]
            commit.diffStatsFetchedAt = commit.authoredAt
        }

        let insights = WorkMetrics(commits: commits).workMapPeriodInsights(
            scope: .week,
            containing: wednesday,
            metric: .changes,
            calendar: calendar
        )

        XCTAssertEqual(insights.activeDayCount, 4)
        XCTAssertEqual(insights.currentStreak, 3)
        XCTAssertEqual(insights.longestStreak, 3)
        XCTAssertEqual(insights.busiestDay?.date, calendar.startOfDay(for: wednesday))
        XCTAssertEqual(insights.medianActiveDayValue, 25)
        XCTAssertEqual(insights.topDayShare, 0.625, accuracy: 0.001)
        XCTAssertEqual(insights.topRepository?.name, "blakecrosley/reps")
        XCTAssertEqual(insights.repositoryCount, 2)
        XCTAssertEqual(insights.firstActiveDate, calendar.startOfDay(for: monday))
        XCTAssertEqual(insights.lastActiveDate, calendar.startOfDay(for: friday))
    }

    func testFailedDiffStatsRetryAfterCooldown() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let commit = makeCommit(
            sha: "eeeeeee222222222222222222222222222222222",
            date: date,
            message: "Retry stats"
        )

        commit.markDiffStatsFailed("network connection lost", fetchedAt: date)

        XCTAssertFalse(commit.needsDiffStatsBackfill(at: date.addingTimeInterval(60)))
        XCTAssertTrue(commit.needsDiffStatsBackfill(at: date.addingTimeInterval(3_601)))
    }

    func testHistoryBackfillPlannerStartsWithAnchorMonth() throws {
        let calendar = utcCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let lowerBound = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))

        let interval = try XCTUnwrap(HistoryBackfillPlanner.monthInterval(
            cursorDate: nil,
            anchorDate: anchor,
            lowerBound: lowerBound,
            calendar: calendar
        ))

        XCTAssertEqual(interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))))
        XCTAssertEqual(interval.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))))
    }

    func testHistoryBackfillPlannerWalksBackwardFromCursor() throws {
        let calendar = utcCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let cursor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let lowerBound = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))

        let interval = try XCTUnwrap(HistoryBackfillPlanner.monthInterval(
            cursorDate: cursor,
            anchorDate: anchor,
            lowerBound: lowerBound,
            calendar: calendar
        ))

        XCTAssertEqual(interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))))
        XCTAssertEqual(interval.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))))
        XCTAssertEqual(HistoryBackfillPlanner.nextCursor(afterCompleted: interval), interval.start)
    }

    func testHistoryBackfillPlannerStopsAtLowerBound() throws {
        let calendar = utcCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let lowerBound = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let cursor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))

        XCTAssertNil(HistoryBackfillPlanner.monthInterval(
            cursorDate: cursor,
            anchorDate: anchor,
            lowerBound: lowerBound,
            calendar: calendar
        ))
    }

    func testVisibleCommitsRespectSelectedRepositories() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let selectedRepository = makeRepository(fullName: "blakecrosley/captains-log", isSelected: true)
        let hiddenRepository = makeRepository(fullName: "blakecrosley/hidden", isSelected: false)
        let visible = makeCommit(
            sha: "fffffff111111111111111111111111111111111",
            repositoryFullName: selectedRepository.fullName,
            date: date,
            message: "Visible work"
        )
        let hidden = makeCommit(
            sha: "ggggggg111111111111111111111111111111111",
            repositoryFullName: hiddenRepository.fullName,
            date: date,
            message: "Hidden work"
        )

        let filtered = WorkDataFilter.visibleCommits(
            [visible, hidden],
            repositories: [selectedRepository, hiddenRepository],
            activeLogin: "blakecrosley"
        )

        XCTAssertEqual(filtered.map(\.id), [visible.id])
    }

    func testVisibleCommitsIncludeUnlinkedAuthorsButExcludeOtherGitHubUsers() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let selectedRepository = makeRepository(fullName: "blakecrosley/hermes-brain", isSelected: true)
        let unlinkedAuthorCommit = makeCommit(
            sha: "aaaaaaa111111111111111111111111111111111",
            repositoryFullName: selectedRepository.fullName,
            authorLogin: nil,
            date: date,
            message: "Unlinked local git author"
        )
        let otherGitHubUserCommit = makeCommit(
            sha: "bbbbbbb111111111111111111111111111111111",
            repositoryFullName: selectedRepository.fullName,
            authorLogin: "someone-else",
            date: date,
            message: "Other GitHub user"
        )

        let filtered = WorkDataFilter.visibleCommits(
            [unlinkedAuthorCommit, otherGitHubUserCommit],
            repositories: [selectedRepository],
            activeLogin: "blakecrosley"
        )

        XCTAssertEqual(filtered.map(\.id), [unlinkedAuthorCommit.id])
    }

    func testVisibleCommitsIncludeConfiguredAuthorAliases() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        let selectedRepository = makeRepository(fullName: "blakecrosley/introl.com", isSelected: true)
        let aliasCommit = makeCommit(
            sha: "ccccccc111111111111111111111111111111111",
            repositoryFullName: selectedRepository.fullName,
            authorLogin: "blakeatintrol",
            date: date,
            message: "Old work identity"
        )

        let filtered = WorkDataFilter.visibleCommits(
            [aliasCommit],
            repositories: [selectedRepository],
            activeLogin: "blakecrosley",
            identityAliases: ["blakeatintrol"]
        )

        XCTAssertEqual(filtered.map(\.id), [aliasCommit.id])
    }

    func testVisibleCommitsCanIncludeAllSelectedRepoActivity() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        let selectedRepository = makeRepository(fullName: "blakecrosley/team-app", isSelected: true)
        let teammateCommit = makeCommit(
            sha: "ddddddd111111111111111111111111111111111",
            repositoryFullName: selectedRepository.fullName,
            authorLogin: "someone-else",
            date: date,
            message: "Team work"
        )

        let filtered = WorkDataFilter.visibleCommits(
            [teammateCommit],
            repositories: [selectedRepository],
            activeLogin: "blakecrosley",
            identityScope: .allSelectedRepos
        )

        XCTAssertEqual(filtered.map(\.id), [teammateCommit.id])
    }

    func testWorkIdentityAliasesPreserveHyphenatedLogins() {
        let aliases = WorkIdentitySelection.aliases(from: "old-blake, blakeatintrol")

        XCTAssertEqual(aliases, ["old-blake", "blakeatintrol"])
    }

    func testWorkLanguageClassifierMapsCommonExtensions() {
        XCTAssertEqual(WorkLanguageClassifier.language(for: "Sources/App.swift"), "Swift")
        XCTAssertEqual(WorkLanguageClassifier.language(for: "web/src/index.tsx"), "TypeScript")
        XCTAssertEqual(WorkLanguageClassifier.language(for: "README.md"), "Docs")
        XCTAssertEqual(WorkLanguageClassifier.language(for: "Dockerfile"), "Docker")
    }

    func testCredentialStoreSupportsInMemoryBYOK() {
        let store = AIProviderCredentialStore(service: "test.captainslog.ai", inMemory: true)

        XCTAssertFalse(store.hasKey(for: .openai))
        XCTAssertTrue(store.saveKey("sk-test", for: .openai))
        XCTAssertEqual(store.loadKey(for: .openai), "sk-test")
        store.deleteKey(for: .openai)
        XCTAssertFalse(store.hasKey(for: .openai))
    }

    func testCredentialStoreShowsMaskedKeyPreview() {
        let store = AIProviderCredentialStore(service: "test.captainslog.preview", inMemory: true)

        XCTAssertNil(store.keyPreview(for: .openai))
        XCTAssertTrue(store.saveKey("sk-proj-abcdef123456", for: .openai))

        XCTAssertEqual(store.keyPreview(for: .openai), "sk-proj-...123456")
    }

    private func makeCommit(
        sha: String,
        repositoryFullName: String = "blakecrosley/captains-log",
        authorLogin: String? = "blakecrosley",
        date: Date,
        message: String
    ) -> GitCommitRecord {
        GitCommitRecord(
            sha: sha,
            repositoryFullName: repositoryFullName,
            authorLogin: authorLogin,
            message: message,
            authoredAt: date,
            htmlURL: nil,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func makeRepository(fullName: String, isSelected: Bool) -> GitRepositoryRecord {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return GitRepositoryRecord(
            id: Int64(abs(fullName.hashValue)),
            ownerLogin: parts.first ?? "owner",
            name: parts.dropFirst().first ?? fullName,
            fullName: fullName,
            accountLogin: "blakecrosley",
            isPrivate: true,
            isSelected: isSelected,
            htmlURL: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }
}
