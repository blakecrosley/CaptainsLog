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
        XCTAssertEqual(WorkRangeScope.allCases.map(\.title), ["Day", "Week", "Quarter", "Year"])
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

        let trend = WorkMetrics(commits: []).trend(scope: .quarter, containing: selectedDate, calendar: calendar)

        XCTAssertEqual(trend.current.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))))
        XCTAssertEqual(trend.baseline.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))))
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
        XCTAssertEqual(snapshot.displayValue, 2)
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
            commit.diffStatsFetchedAt = date
        }

        let snapshot = WorkMetrics(commits: commits).snapshot(on: date, calendar: calendar)

        XCTAssertEqual(snapshot.mode, .diffBacked)
        XCTAssertEqual(snapshot.workUnits, 50)
        XCTAssertEqual(snapshot.displayValue, 50)
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

    private func makeCommit(sha: String, date: Date, message: String) -> GitCommitRecord {
        GitCommitRecord(
            sha: sha,
            repositoryFullName: "blakecrosley/captains-log",
            authorLogin: "blakecrosley",
            message: message,
            authoredAt: date,
            htmlURL: nil,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
