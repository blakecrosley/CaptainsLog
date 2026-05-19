import XCTest
@testable import Captain_s_Log

final class CompanionSnapshotTests: XCTestCase {
    func testCompanionSnapshotUsesAggregateMetricsWithoutPrivateWorkText() throws {
        let date = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 10)))
        let repository = GitRepositoryRecord(
            id: 941,
            ownerLogin: "blakecrosley",
            name: "private-repo",
            fullName: "blakecrosley/private-repo",
            isPrivate: true,
            isSelected: true
        )
        let commit = GitCommitRecord(
            sha: "abcdef1234567890",
            repositoryFullName: repository.fullName,
            authorLogin: "blakecrosley",
            message: "Secret project codename",
            authoredAt: date,
            htmlURL: nil,
            calendar: Self.calendar
        )
        commit.applyDiffStats(additions: 120, deletions: 30, changedFileCount: 4)

        let summary = DailyJournalSummaryRecord(
            date: date,
            title: "Launch codename",
            narrative: "Private narrative",
            bullets: ["Private bullet"],
            tags: ["private"],
            sourceCommitIDs: [commit.id]
        )

        let snapshot = CompanionSnapshotBuilder.makeSnapshot(
            selectedDate: date,
            workMetrics: WorkMetrics(commits: [commit]),
            summaries: [summary],
            repositories: [repository],
            calendar: Self.calendar,
            now: date
        )
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))

        XCTAssertEqual(snapshot.primary.value, "150 lines")
        XCTAssertEqual(snapshot.journal.value, "Ready")
        XCTAssertEqual(snapshot.repositories.value, "1 of 1")
        XCTAssertFalse(encoded.contains("private-repo"))
        XCTAssertFalse(encoded.contains("Secret project codename"))
        XCTAssertFalse(encoded.contains("Launch codename"))
        XCTAssertFalse(encoded.contains("Private narrative"))
    }

    func testCompanionSnapshotFallsBackToCommitCountsWhenDiffStatsAreMissing() throws {
        let date = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 10)))
        let repository = GitRepositoryRecord(
            id: 1,
            ownerLogin: "blakecrosley",
            name: "captains-log",
            fullName: "blakecrosley/captains-log",
            isPrivate: true,
            isSelected: true
        )
        let commit = GitCommitRecord(
            sha: "bbbbbb1234567890",
            repositoryFullName: repository.fullName,
            authorLogin: "blakecrosley",
            message: "Build snapshot sync",
            authoredAt: date,
            htmlURL: nil,
            calendar: Self.calendar
        )

        let snapshot = CompanionSnapshotBuilder.makeSnapshot(
            selectedDate: date,
            workMetrics: WorkMetrics(commits: [commit]),
            summaries: [],
            repositories: [repository],
            calendar: Self.calendar,
            now: date
        )

        XCTAssertEqual(snapshot.primary.value, "1 commit")
        XCTAssertEqual(snapshot.journal.value, "Generate")
    }

    func testCompanionSnapshotPayloadRoundTrips() throws {
        let snapshot = CompanionSnapshot.placeholder
        let payload = CompanionSnapshotSync.payload(for: snapshot)

        XCTAssertEqual(CompanionSnapshotSync.snapshot(from: payload), snapshot)
        XCTAssertTrue(CompanionSnapshotSync.isSnapshotRequest(CompanionSnapshotSync.requestSnapshotPayload()))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
