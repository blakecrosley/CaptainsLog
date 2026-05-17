import Foundation
import SwiftData

@Model
final class GitHubAccountRecord {
    @Attribute(.unique) var login: String
    var name: String?
    var avatarURL: URL?
    var htmlURL: URL?
    var isActive: Bool
    var lastUsedAt: Date

    init(
        login: String,
        name: String?,
        avatarURL: URL?,
        htmlURL: URL?,
        isActive: Bool = true,
        lastUsedAt: Date = Date()
    ) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.htmlURL = htmlURL
        self.isActive = isActive
        self.lastUsedAt = lastUsedAt
    }

    func update(from viewer: GitHubViewer, isActive: Bool) {
        login = viewer.login
        name = viewer.name
        avatarURL = viewer.avatarURL
        htmlURL = viewer.htmlURL
        self.isActive = isActive
        lastUsedAt = Date()
    }
}

@Model
final class GitRepositoryRecord {
    @Attribute(.unique) var id: Int64
    var ownerLogin: String
    var name: String
    var fullName: String
    var accountLogin: String?
    var isPrivate: Bool
    var isSelected: Bool
    var htmlURL: URL?
    var pushedAt: Date?
    var lastSyncedAt: Date?
    var createdAt: Date
    var historyBackfillLowerBound: Date?
    var historyBackfillCursorDate: Date?
    var historyBackfillMonthStart: Date?
    var historyBackfillMonthEnd: Date?
    var historyBackfillPageCursor: String?
    var historyBackfillCompletedAt: Date?
    var historyBackfillLastAttemptAt: Date?
    var historyBackfillLastError: String?
    var historyBackfillProcessedCommitCount: Int?
    var historyBackfillUpdatedStatCount: Int?

    @Relationship(deleteRule: .cascade, inverse: \GitCommitRecord.repository)
    var commits: [GitCommitRecord]

    var isGitHubBacked: Bool {
        id > 0
    }

    init(
        id: Int64,
        ownerLogin: String,
        name: String,
        fullName: String,
        accountLogin: String? = nil,
        isPrivate: Bool,
        isSelected: Bool = true,
        htmlURL: URL? = nil,
        pushedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerLogin = ownerLogin
        self.name = name
        self.fullName = fullName
        self.accountLogin = accountLogin
        self.isPrivate = isPrivate
        self.isSelected = isSelected
        self.htmlURL = htmlURL
        self.pushedAt = pushedAt
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.historyBackfillLowerBound = nil
        self.historyBackfillCursorDate = nil
        self.historyBackfillMonthStart = nil
        self.historyBackfillMonthEnd = nil
        self.historyBackfillPageCursor = nil
        self.historyBackfillCompletedAt = nil
        self.historyBackfillLastAttemptAt = nil
        self.historyBackfillLastError = nil
        self.historyBackfillProcessedCommitCount = nil
        self.historyBackfillUpdatedStatCount = nil
        self.commits = []
    }

    var isHistoryBackfillComplete: Bool {
        historyBackfillCompletedAt != nil
    }

    func prepareHistoryBackfill(lowerBound: Date) {
        if let previousLowerBound = historyBackfillLowerBound, previousLowerBound > lowerBound {
            historyBackfillCompletedAt = nil
        }
        historyBackfillLowerBound = lowerBound
    }

    func markHistoryBackfillMonth(
        _ interval: DateInterval,
        pageCursor: String? = nil,
        attemptedAt: Date = Date()
    ) {
        historyBackfillMonthStart = interval.start
        historyBackfillMonthEnd = interval.end
        historyBackfillPageCursor = pageCursor
        historyBackfillLastAttemptAt = attemptedAt
        historyBackfillLastError = nil
        historyBackfillCompletedAt = nil
    }

    func advanceHistoryBackfillCursor(to date: Date, completedAt: Date? = nil) {
        historyBackfillCursorDate = date
        historyBackfillMonthStart = nil
        historyBackfillMonthEnd = nil
        historyBackfillPageCursor = nil
        historyBackfillCompletedAt = completedAt
        historyBackfillLastError = nil
    }

    func markHistoryBackfillFailed(_ message: String, attemptedAt: Date = Date()) {
        historyBackfillLastAttemptAt = attemptedAt
        historyBackfillLastError = message
    }

    func recordHistoryBackfillProgress(processedCommits: Int, updatedStats: Int) {
        historyBackfillProcessedCommitCount = (historyBackfillProcessedCommitCount ?? 0) + processedCommits
        historyBackfillUpdatedStatCount = (historyBackfillUpdatedStatCount ?? 0) + updatedStats
    }
}

@Model
final class GitCommitRecord {
    @Attribute(.unique) var id: String
    var sha: String
    var shortSHA: String
    var repositoryFullName: String
    var authorLogin: String?
    var messageHeadline: String
    var messageBody: String
    var authoredAt: Date
    var dayKey: String
    var htmlURL: URL?
    var insertedAt: Date
    var additions: Int?
    var deletions: Int?
    var totalChanges: Int?
    var changedFileCount: Int?
    var changedFilesBlob: String?
    var diffStatsFetchedAt: Date?
    var diffStatsError: String?
    var repository: GitRepositoryRecord?

    init(
        sha: String,
        repositoryFullName: String,
        authorLogin: String?,
        message: String,
        authoredAt: Date,
        htmlURL: URL?,
        calendar: Calendar = .current
    ) {
        self.id = "\(repositoryFullName)#\(sha)"
        self.sha = sha
        self.shortSHA = String(sha.prefix(7))
        self.repositoryFullName = repositoryFullName
        self.authorLogin = authorLogin
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        self.messageHeadline = parts.first.map(String.init) ?? "Untitled commit"
        self.messageBody = parts.dropFirst().first.map(String.init) ?? ""
        self.authoredAt = authoredAt
        self.dayKey = Self.dayKey(for: authoredAt, calendar: calendar)
        self.htmlURL = htmlURL
        self.insertedAt = Date()
        self.additions = nil
        self.deletions = nil
        self.totalChanges = nil
        self.changedFileCount = nil
        self.changedFilesBlob = nil
        self.diffStatsFetchedAt = nil
        self.diffStatsError = nil
    }

    var hasDiffStats: Bool {
        additions != nil && deletions != nil && changedFileCount != nil
    }

    func needsDiffStatsBackfill(
        at date: Date = Date(),
        retryInterval: TimeInterval = 3_600
    ) -> Bool {
        guard !hasDiffStats else {
            return false
        }
        guard diffStatsError != nil, let diffStatsFetchedAt else {
            return true
        }
        return date.timeIntervalSince(diffStatsFetchedAt) >= retryInterval
    }

    var changedFiles: [String] {
        get {
            changedFilesBlob?
                .split(separator: "\n")
                .map(String.init) ?? []
        }
        set {
            changedFilesBlob = newValue.isEmpty ? nil : newValue.joined(separator: "\n")
        }
    }

    func applyDiffStats(from detail: GitHubCommitDetailDTO, fetchedAt: Date = Date()) {
        additions = detail.stats?.additions
        deletions = detail.stats?.deletions
        totalChanges = detail.stats?.total
        changedFileCount = detail.files.count
        changedFiles = detail.files.map(\.filename)
        diffStatsFetchedAt = fetchedAt
        diffStatsError = nil
    }

    func applyDiffStats(
        additions: Int,
        deletions: Int,
        changedFileCount: Int?,
        fetchedAt: Date = Date()
    ) {
        self.additions = additions
        self.deletions = deletions
        totalChanges = additions + deletions
        self.changedFileCount = changedFileCount
        diffStatsFetchedAt = fetchedAt
        diffStatsError = nil
    }

    func markDiffStatsFailed(_ message: String, fetchedAt: Date = Date()) {
        diffStatsFetchedAt = fetchedAt
        diffStatsError = message
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

@Model
final class DailyJournalSummaryRecord {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var title: String
    var narrative: String
    var bulletsBlob: String
    var tagsBlob: String
    var sourceCommitIDsBlob: String
    var generatedAt: Date
    var modelName: String
    var isLocked: Bool = false

    init(
        date: Date,
        title: String,
        narrative: String,
        bullets: [String],
        tags: [String],
        sourceCommitIDs: [String],
        generatedAt: Date = Date(),
        modelName: String = "Apple Foundation Models",
        isLocked: Bool = false
    ) {
        self.dayKey = GitCommitRecord.dayKey(for: date)
        self.date = date
        self.title = title
        self.narrative = narrative
        self.bulletsBlob = bullets.joined(separator: "\n")
        self.tagsBlob = tags.joined(separator: "\n")
        self.sourceCommitIDsBlob = sourceCommitIDs.joined(separator: "\n")
        self.generatedAt = generatedAt
        self.modelName = modelName
        self.isLocked = isLocked
    }

    var bullets: [String] {
        bulletsBlob.split(separator: "\n").map(String.init)
    }

    var tags: [String] {
        tagsBlob.split(separator: "\n").map(String.init)
    }

    var sourceCommitIDs: [String] {
        sourceCommitIDsBlob.split(separator: "\n").map(String.init)
    }

    @discardableResult
    func update(from draft: JournalSummaryDraft, sourceCommitIDs: [String], modelName: String) -> Bool {
        guard !isLocked else {
            return false
        }

        title = draft.title
        narrative = draft.narrative
        bulletsBlob = draft.bullets.joined(separator: "\n")
        tagsBlob = draft.tags.joined(separator: "\n")
        sourceCommitIDsBlob = sourceCommitIDs.joined(separator: "\n")
        generatedAt = Date()
        self.modelName = modelName
        return true
    }
}

struct ActivityMetrics {
    let commitsByDay: [String: [GitCommitRecord]]

    init(commits: [GitCommitRecord]) {
        self.commitsByDay = Dictionary(grouping: commits, by: \.dayKey)
    }

    func count(on date: Date, calendar: Calendar = .current) -> Int {
        commitsByDay[GitCommitRecord.dayKey(for: date, calendar: calendar)]?.count ?? 0
    }

    func commits(on date: Date, calendar: Calendar = .current) -> [GitCommitRecord] {
        let key = GitCommitRecord.dayKey(for: date, calendar: calendar)
        return (commitsByDay[key] ?? []).sorted { $0.authoredAt > $1.authoredAt }
    }
}

enum WorkDataFilter {
    static func visibleCommits(
        _ commits: [GitCommitRecord],
        repositories: [GitRepositoryRecord],
        activeLogin: String?,
        identityScope: WorkIdentityScope = .mineAndAliases,
        identityAliases: Set<String> = []
    ) -> [GitCommitRecord] {
        let identity = WorkIdentitySelection(
            activeLogin: activeLogin,
            scope: identityScope,
            aliases: identityAliases
        )
        let selectedRepositoryNames = Set(
            repositories
                .filter { repository in
                    guard repository.isSelected else {
                        return false
                    }
                    guard repository.isGitHubBacked, let activeLogin else {
                        return true
                    }
                    return repository.accountLogin == nil || repository.accountLogin == activeLogin
                }
                .map(\.fullName)
        )

        guard !selectedRepositoryNames.isEmpty else {
            return []
        }

        return commits.filter { commit in
            guard selectedRepositoryNames.contains(commit.repositoryFullName) else {
                return false
            }
            return identity.includes(authorLogin: commit.authorLogin)
        }
    }
}
