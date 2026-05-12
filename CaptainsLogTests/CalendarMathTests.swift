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
