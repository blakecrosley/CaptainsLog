import Foundation
import SwiftData
import SwiftUI

enum RepositorySyncWindow {
    static func updateSince(
        fallbackSince: Date,
        lastSyncedAt: Date?,
        newestCommitDate: Date?,
        overlap: TimeInterval
    ) -> Date {
        [
            fallbackSince,
            lastSyncedAt?.addingTimeInterval(-overlap),
            newestCommitDate?.addingTimeInterval(-overlap)
        ]
        .compactMap { $0 }
        .max() ?? fallbackSince
    }
}

enum RepositoryHistoryBackfillPolicy {
    static let fullSyncCommitPageLimit: Int? = nil
}

private enum DiffStatsBackfillOrder {
    case newestFirst
    case oldestFirst
}

private struct RepositorySyncResult {
    let updateSince: Date
    let usedHistoryStats: Bool
}

@MainActor
final class AppModel: ObservableObject {
    enum AuthState: Equatable {
        case signedOut
        case requestingCode
        case waitingForUser(GitHubDeviceCodeResponse)
        case completingSignIn(GitHubDeviceCodeResponse)
        case signedIn(GitHubViewer)
        case failed(String)
    }

    @Published private(set) var authState: AuthState = .signedOut
    @Published private(set) var isSyncing = false
    @Published private(set) var syncMessage = ""
    @Published private(set) var authMessage = ""
    @Published private(set) var importedCommitCount = 0
    @Published private(set) var updatedDiffStatCount = 0
    @Published private(set) var foundationAvailability = JournalSummarizer.availability()
    @Published private(set) var repositoryApprovalURL = GitHubAppConfiguration.installURL

    private var modelContext: ModelContext?
    private var token: String?
    private var viewer: GitHubViewer?
    private var pendingDeviceCode: GitHubDeviceCodeResponse?
    private let commitPageSize = 100
    private let commitSyncOverlap: TimeInterval = 300
    private let diffStatsBackfillPerRepositoryLimit = 100
    private let diffStatsBackfillPerSyncLimit = 300
    private let todayDiffStatsPerRepositoryLimit = 20
    private let todayDiffStatsPerSyncLimit = 80
    private let incrementalDiffStatsPerRepositoryLimit = 25
    private let incrementalDiffStatsPerSyncLimit = 100
    private let historicalBackfillCommitPagesPerRepository = RepositoryHistoryBackfillPolicy.fullSyncCommitPageLimit

    var isSignedIn: Bool {
        token != nil && viewer != nil
    }

    var githubClientID: String {
        GitHubAppConfiguration.clientID
    }

    var githubAppSlug: String {
        GitHubAppConfiguration.appSlug
    }

    var githubAppInstallURL: URL? {
        GitHubAppConfiguration.installURL
    }

    var githubRepositoryApprovalURL: URL? {
        repositoryApprovalURL ?? githubAppInstallURL
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadSession() async {
        foundationAvailability = JournalSummarizer.availability()
        do {
            guard let savedToken = try KeychainTokenStore.readToken() else {
                authState = .signedOut
                return
            }
            token = savedToken
            let loadedViewer = try await GitHubAPIClient(token: savedToken, appSlug: githubAppSlug).viewer()
            viewer = loadedViewer
            if let modelContext {
                try deleteDemoData(modelContext: modelContext)
                try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
                try modelContext.save()
            }
            try KeychainTokenStore.saveToken(savedToken, login: loadedViewer.login)
            authState = .signedIn(loadedViewer)
        } catch {
            token = nil
            viewer = nil
            authState = .failed(error.localizedDescription)
        }
    }

    func signIn() async {
        guard !githubClientID.isEmpty else {
            authState = .failed("GitHub sign-in is not configured yet. Add the Captain's Log GitHub App Client ID to the GITHUB_CLIENT_ID build setting.")
            return
        }

        authMessage = ""
        authState = .requestingCode
        do {
            let auth = GitHubDeviceAuthService(clientID: githubClientID)
            let code = try await auth.requestDeviceCode()
            pendingDeviceCode = code
            authState = .waitingForUser(code)
        } catch {
            authState = .failed(error.localizedDescription)
        }
    }

    func completePendingSignIn() async {
        guard let code = pendingDeviceCode else {
            return
        }
        if case .completingSignIn = authState {
            return
        }

        authState = .completingSignIn(code)
        do {
            let auth = GitHubDeviceAuthService(clientID: githubClientID)
            guard let accessToken = try await auth.exchangeDeviceCode(deviceCode: code.deviceCode) else {
                authState = .waitingForUser(code)
                authMessage = "GitHub has not confirmed this code yet."
                return
            }
            let loadedViewer = try await GitHubAPIClient(token: accessToken, appSlug: githubAppSlug).viewer()
            try KeychainTokenStore.saveToken(accessToken, login: loadedViewer.login)
            token = accessToken
            pendingDeviceCode = nil
            authMessage = ""
            viewer = loadedViewer
            if let modelContext {
                try deleteDemoData(modelContext: modelContext)
                try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
                try modelContext.save()
            }
            authState = .signedIn(loadedViewer)
        } catch {
            authState = .waitingForUser(code)
            authMessage = error.localizedDescription
        }
    }

    func signOut() {
        if let viewer {
            try? KeychainTokenStore.deleteToken(login: viewer.login)
        } else {
            try? KeychainTokenStore.deleteToken()
        }
        token = nil
        viewer = nil
        pendingDeviceCode = nil
        authMessage = ""
        repositoryApprovalURL = githubAppInstallURL
        authState = .signedOut
    }

    func switchAccount(_ account: GitHubAccountRecord) async {
        guard let modelContext else {
            authState = .failed(StorageError.missingModelContext.localizedDescription)
            return
        }

        do {
            guard let savedToken = try KeychainTokenStore.readToken(login: account.login) else {
                authState = .failed("Sign in to @\(account.login) again.")
                return
            }
            let loadedViewer = try await GitHubAPIClient(token: savedToken, appSlug: githubAppSlug).viewer()
            try KeychainTokenStore.saveActiveLogin(loadedViewer.login)
            token = savedToken
            viewer = loadedViewer
            try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
            try modelContext.save()
            authState = .signedIn(loadedViewer)
        } catch {
            authState = .failed(error.localizedDescription)
        }
    }

    func refreshRepositories() async {
        guard !isSyncing else {
            return
        }
        guard let token else {
            authState = .signedOut
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            return
        }

        isSyncing = true
        syncMessage = "Loading repositories"
        defer { isSyncing = false }

        do {
            let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
            let access = try await api.repositoryAccess()
            repositoryApprovalURL = access.approvalURL ?? githubAppInstallURL
            try deleteDemoData(modelContext: modelContext)
            try upsertRepositories(access.repositories, accountLogin: viewer?.login, modelContext: modelContext)
            if !access.canReadContents {
                syncMessage = "Set Contents to read-only in the GitHub App permissions, then approve repository access."
            } else if access.repositories.isEmpty {
                syncMessage = "Approve access to all repositories or selected repositories in GitHub."
            } else {
                syncMessage = "Loaded \(access.repositories.count) repositories"
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func syncSelectedRepositories(
        lookbackDays: Int = 370
    ) async {
        guard !isSyncing else {
            return
        }
        guard let token, let viewer else {
            authState = .signedOut
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            return
        }

        isSyncing = true
        importedCommitCount = 0
        updatedDiffStatCount = 0
        syncMessage = "Syncing updates"
        defer { isSyncing = false }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        let fallbackSince = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        var failedRepositories: [(name: String, message: String)] = []

        do {
            let selected = try selectedRepositories(modelContext: modelContext)
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return
            }

            var diffStatsBudget = incrementalDiffStatsPerSyncLimit
            for repository in selected {
                do {
                    let syncResult = try await syncRepositoryCommits(
                        repository,
                        api: api,
                        author: viewer.login,
                        authorID: viewer.nodeID,
                        fallbackSince: fallbackSince,
                        phase: "Syncing updates",
                        backfillHistoricalGaps: false,
                        modelContext: modelContext
                    )
                    if !syncResult.usedHistoryStats, diffStatsBudget > 0 {
                        let result = try await backfillDiffStats(
                            repository,
                            api: api,
                            requestLimit: min(incrementalDiffStatsPerRepositoryLimit, diffStatsBudget),
                            authoredSince: syncResult.updateSince,
                            modelContext: modelContext
                        )
                        diffStatsBudget -= result.attempted
                    }
                } catch is CancellationError {
                    syncMessage = "Sync canceled"
                    return
                } catch {
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                syncMessage = syncCompleteMessage(failedRepositoryCount: 0)
            } else if importedCommitCount > 0 {
                syncMessage = syncCompleteMessage(failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Sync failed"
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func fullSyncSelectedRepositories(
        lookbackDays: Int = 7_300
    ) async {
        guard !isSyncing else {
            return
        }
        guard let token, let viewer else {
            authState = .signedOut
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            return
        }

        isSyncing = true
        importedCommitCount = 0
        updatedDiffStatCount = 0
        syncMessage = "Backfilling full history"
        defer { isSyncing = false }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        let fallbackSince = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        var failedRepositories: [(name: String, message: String)] = []

        do {
            let selected = try selectedRepositories(modelContext: modelContext)
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return
            }

            var diffStatsBudget = diffStatsBackfillPerSyncLimit
            for repository in selected {
                do {
                    let usedHistoryStats = try await backfillRepositoryHistory(
                        repository,
                        api: api,
                        author: viewer.login,
                        authorID: viewer.nodeID,
                        since: fallbackSince,
                        maxPages: historicalBackfillCommitPagesPerRepository,
                        modelContext: modelContext
                    )
                    if !usedHistoryStats, diffStatsBudget > 0 {
                        let result = try await backfillDiffStats(
                            repository,
                            api: api,
                            requestLimit: min(diffStatsBackfillPerRepositoryLimit, diffStatsBudget),
                            order: .newestFirst,
                            modelContext: modelContext
                        )
                        diffStatsBudget -= result.attempted
                    }
                } catch is CancellationError {
                    syncMessage = "Backfill canceled"
                    return
                } catch {
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                syncMessage = syncCompleteMessage(prefix: "Backfill complete", failedRepositoryCount: 0)
            } else if importedCommitCount > 0 || updatedDiffStatCount > 0 {
                syncMessage = syncCompleteMessage(prefix: "Backfill complete", failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Backfill failed"
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func syncToday() async {
        guard !isSyncing else {
            return
        }
        guard let token, let viewer else {
            authState = .signedOut
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            return
        }

        isSyncing = true
        importedCommitCount = 0
        updatedDiffStatCount = 0
        syncMessage = "Refreshing today"
        defer { isSyncing = false }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var failedRepositories: [(name: String, message: String)] = []

        do {
            let selected = try selectedRepositories(modelContext: modelContext)
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return
            }

            var diffStatsBudget = todayDiffStatsPerSyncLimit
            for repository in selected {
                do {
                    let syncResult = try await syncRepositoryCommits(
                        repository,
                        api: api,
                        author: viewer.login,
                        authorID: viewer.nodeID,
                        fallbackSince: startOfToday,
                        phase: "Refreshing today",
                        backfillHistoricalGaps: false,
                        modelContext: modelContext
                    )
                    if !syncResult.usedHistoryStats, diffStatsBudget > 0 {
                        let result = try await backfillDiffStats(
                            repository,
                            api: api,
                            requestLimit: min(todayDiffStatsPerRepositoryLimit, diffStatsBudget),
                            authoredSince: syncResult.updateSince,
                            modelContext: modelContext
                        )
                        diffStatsBudget -= result.attempted
                    }
                } catch is CancellationError {
                    syncMessage = "Refresh canceled"
                    return
                } catch {
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                syncMessage = todaySyncCompleteMessage(failedRepositoryCount: 0)
            } else if importedCommitCount > 0 || updatedDiffStatCount > 0 {
                syncMessage = todaySyncCompleteMessage(failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Refresh failed"
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func seedDemoData() throws {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }

        let repo = try demoRepository(modelContext: modelContext)
        let calendar = Calendar.current
        let subjects = [
            "Add GitHub device auth shell",
            "Build contribution heatmap",
            "Port week calendar from Reps",
            "Draft Foundation Models journal prompt",
            "Tighten repository picker empty state",
            "Store summary source commit IDs"
        ]

        for offset in 0..<18 {
            guard offset % 3 != 1,
                  let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                continue
            }

            let commitsForDay = (offset % 4) + 1
            for index in 0..<commitsForDay {
                let sha = "demo\(offset)\(index)00000000000000000000000000000000000"
                let record = GitCommitRecord(
                    sha: sha,
                    repositoryFullName: repo.fullName,
                    authorLogin: "demo",
                    message: subjects[(offset + index) % subjects.count],
                    authoredAt: calendar.date(byAdding: .hour, value: index + 9, to: calendar.startOfDay(for: date)) ?? date,
                    htmlURL: nil
                )
                record.repository = repo
                if try !commitExists(id: record.id, modelContext: modelContext) {
                    modelContext.insert(record)
                }
            }
        }

        try modelContext.save()
        syncMessage = "Seeded demo commits"
    }

    func saveSummary(
        date: Date,
        draft: JournalSummaryDraft,
        sourceCommitIDs: [String],
        modelName: String = "Apple Foundation Models"
    ) throws {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }

        let dayKey = GitCommitRecord.dayKey(for: date)
        var descriptor = FetchDescriptor<DailyJournalSummaryRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: draft, sourceCommitIDs: sourceCommitIDs, modelName: modelName)
        } else {
            modelContext.insert(
                DailyJournalSummaryRecord(
                    date: Calendar.current.startOfDay(for: date),
                    title: draft.title,
                    narrative: draft.narrative,
                    bullets: draft.bullets,
                    tags: draft.tags,
                    sourceCommitIDs: sourceCommitIDs,
                    modelName: modelName
                )
            )
        }

        try modelContext.save()
    }

    private func upsertRepositories(
        _ remoteRepos: [GitHubRepositoryDTO],
        accountLogin: String?,
        modelContext: ModelContext
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<GitRepositoryRecord>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let remoteIDs = Set(remoteRepos.map(\.id))

        if let accountLogin {
            for record in existing where record.isGitHubBacked && record.accountLogin == accountLogin && !remoteIDs.contains(record.id) {
                modelContext.delete(record)
                byID[record.id] = nil
            }
        }

        for remote in remoteRepos {
            if let record = byID[remote.id] {
                record.ownerLogin = remote.owner.login
                record.name = remote.name
                record.fullName = remote.fullName
                record.accountLogin = accountLogin
                record.isPrivate = remote.isPrivate
                record.htmlURL = remote.htmlURL
                record.pushedAt = remote.pushedAt
            } else {
                let record = GitRepositoryRecord(
                    id: remote.id,
                    ownerLogin: remote.owner.login,
                    name: remote.name,
                    fullName: remote.fullName,
                    accountLogin: accountLogin,
                    isPrivate: remote.isPrivate,
                    htmlURL: remote.htmlURL,
                    pushedAt: remote.pushedAt
                )
                modelContext.insert(record)
                byID[remote.id] = record
            }
        }

        try modelContext.save()
    }

    private func upsertAccount(
        _ viewer: GitHubViewer,
        isActive: Bool,
        modelContext: ModelContext
    ) throws {
        let login = viewer.login
        let descriptor = FetchDescriptor<GitHubAccountRecord>(
            predicate: #Predicate { $0.login == login }
        )

        if isActive {
            let allAccounts = try modelContext.fetch(FetchDescriptor<GitHubAccountRecord>())
            for account in allAccounts {
                account.isActive = account.login == login
            }
        }

        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: viewer, isActive: isActive)
        } else {
            modelContext.insert(
                GitHubAccountRecord(
                    login: viewer.login,
                    name: viewer.name,
                    avatarURL: viewer.avatarURL,
                    htmlURL: viewer.htmlURL,
                    isActive: isActive
                )
            )
        }
    }

    private func upsertCommits(
        _ remoteCommits: [GitHubCommitDTO],
        repository: GitRepositoryRecord,
        author: String,
        existingCommitIDs: inout Set<String>,
        modelContext: ModelContext
    ) throws -> Int {
        var inserted = 0
        for remote in remoteCommits {
            let id = "\(repository.fullName)#\(remote.sha)"
            guard !existingCommitIDs.contains(id) else {
                continue
            }

            let record = GitCommitRecord(
                sha: remote.sha,
                repositoryFullName: repository.fullName,
                authorLogin: remote.author?.login ?? author,
                message: remote.message,
                authoredAt: remote.authoredAt,
                htmlURL: remote.htmlURL
            )
            record.repository = repository
            modelContext.insert(record)
            existingCommitIDs.insert(id)
            inserted += 1
        }
        return inserted
    }

    private func upsertGraphQLCommits(
        _ remoteCommits: [GitHubGraphQLCommitDTO],
        repository: GitRepositoryRecord,
        author: String,
        existingCommits: inout [String: GitCommitRecord],
        modelContext: ModelContext
    ) throws -> (inserted: Int, updatedStats: Int) {
        var inserted = 0
        var updatedStats = 0

        for remote in remoteCommits {
            let id = "\(repository.fullName)#\(remote.oid)"
            let record: GitCommitRecord

            if let existing = existingCommits[id] {
                record = existing
            } else {
                record = GitCommitRecord(
                    sha: remote.oid,
                    repositoryFullName: repository.fullName,
                    authorLogin: remote.authorLogin ?? author,
                    message: remote.message,
                    authoredAt: remote.authoredDate,
                    htmlURL: remote.url
                )
                record.repository = repository
                modelContext.insert(record)
                existingCommits[id] = record
                inserted += 1
            }

            let changedFileCount = remote.changedFilesIfAvailable ?? 0
            if record.additions != remote.additions ||
                record.deletions != remote.deletions ||
                record.changedFileCount != changedFileCount {
                record.applyDiffStats(
                    additions: remote.additions,
                    deletions: remote.deletions,
                    changedFileCount: changedFileCount
                )
                updatedStats += 1
            }
        }

        return (inserted, updatedStats)
    }

    private func syncRepositoryCommits(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        authorID: String?,
        fallbackSince: Date,
        phase: String = "Syncing",
        backfillHistoricalGaps: Bool = true,
        modelContext: ModelContext
    ) async throws -> RepositorySyncResult {
        let newestCommitDate = try newestCommitDate(
            repositoryFullName: repository.fullName,
            modelContext: modelContext
        )
        let updateSince = RepositorySyncWindow.updateSince(
            fallbackSince: fallbackSince,
            lastSyncedAt: repository.lastSyncedAt,
            newestCommitDate: newestCommitDate,
            overlap: commitSyncOverlap
        )
        var existingCommitIDs: Set<String>?
        let usedHistoryStats = try await syncCommitHistoryPagesIfAvailable(
            repository,
            api: api,
            author: author,
            authorID: authorID,
            since: updateSince,
            until: nil,
            phase: phase,
            maxPages: nil,
            modelContext: modelContext
        )
        if !usedHistoryStats {
            var fallbackCommitIDs = try self.existingCommitIDs(
                repositoryFullName: repository.fullName,
                authoredSince: backfillHistoricalGaps ? nil : updateSince,
                modelContext: modelContext
            )

            try await syncCommitPages(
                repository,
                api: api,
                author: author,
                since: updateSince,
                until: nil,
                phase: phase,
                existingCommitIDs: &fallbackCommitIDs,
                modelContext: modelContext
            )
            existingCommitIDs = fallbackCommitIDs
        }

        guard backfillHistoricalGaps else {
            repository.lastSyncedAt = Date()
            try modelContext.save()
            return RepositorySyncResult(updateSince: updateSince, usedHistoryStats: usedHistoryStats)
        }

        if let oldestCommitDate = try oldestCommitDate(
            repositoryFullName: repository.fullName,
            modelContext: modelContext
        ) {
            let backfillUntil = oldestCommitDate.addingTimeInterval(-1)
            if backfillUntil > fallbackSince {
                var fallbackCommitIDs: Set<String>
                if let existingCommitIDs {
                    fallbackCommitIDs = existingCommitIDs
                } else {
                    fallbackCommitIDs = try self.existingCommitIDs(
                        repositoryFullName: repository.fullName,
                        modelContext: modelContext
                    )
                }
                try await syncCommitPages(
                    repository,
                    api: api,
                    author: author,
                    since: fallbackSince,
                    until: backfillUntil,
                    phase: "Backfilling",
                    existingCommitIDs: &fallbackCommitIDs,
                    modelContext: modelContext
                )
                existingCommitIDs = fallbackCommitIDs
            }
        }

        repository.lastSyncedAt = Date()
        try modelContext.save()
        return RepositorySyncResult(updateSince: updateSince, usedHistoryStats: usedHistoryStats)
    }

    private func backfillRepositoryHistory(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        authorID: String?,
        since: Date,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        var usedHistoryStats = try await syncMissingDiffStatsFromHistory(
            repository,
            api: api,
            author: author,
            authorID: authorID,
            since: since,
            maxPages: maxPages,
            modelContext: modelContext
        )

        let oldestCommitDate = try oldestCommitDate(
            repositoryFullName: repository.fullName,
            modelContext: modelContext
        )
        let until = oldestCommitDate?.addingTimeInterval(-1)
        let usedOlderHistory = try await syncCommitHistoryPagesIfAvailable(
            repository,
            api: api,
            author: author,
            authorID: authorID,
            since: since,
            until: until,
            phase: "Backfilling history",
            maxPages: maxPages,
            modelContext: modelContext
        )
        usedHistoryStats = usedHistoryStats || usedOlderHistory
        if !usedOlderHistory {
            var existingCommitIDs = try existingCommitIDs(
                repositoryFullName: repository.fullName,
                modelContext: modelContext
            )

            try await syncCommitPages(
                repository,
                api: api,
                author: author,
                since: since,
                until: until,
                phase: "Backfilling history",
                maxPages: maxPages,
                existingCommitIDs: &existingCommitIDs,
                modelContext: modelContext
            )
        }

        repository.lastSyncedAt = Date()
        try modelContext.save()
        return usedHistoryStats
    }

    private func syncMissingDiffStatsFromHistory(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        authorID: String?,
        since: Date,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard let window = try missingDiffStatsWindow(
            repositoryFullName: repository.fullName,
            since: since,
            modelContext: modelContext
        ) else {
            return false
        }

        return try await syncCommitHistoryPagesIfAvailable(
            repository,
            api: api,
            author: author,
            authorID: authorID,
            since: window.start,
            until: window.end,
            phase: "Backfilling line stats",
            maxPages: maxPages,
            modelContext: modelContext
        )
    }

    private func syncCommitHistoryPagesIfAvailable(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        authorID: String?,
        since: Date,
        until: Date?,
        phase: String,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        do {
            return try await syncCommitHistoryPages(
                repository,
                api: api,
                author: author,
                authorID: authorID,
                since: since,
                until: until,
                phase: phase,
                maxPages: maxPages,
                modelContext: modelContext
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            syncMessage = "GitHub history stats unavailable for \(repository.fullName); using REST"
            return false
        }
    }

    private func syncCommitHistoryPages(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        authorID: String?,
        since: Date,
        until: Date?,
        phase: String,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard let authorID, !authorID.isEmpty else {
            return false
        }

        var existingCommits = try existingCommitRecords(
            repositoryFullName: repository.fullName,
            authoredSince: until == nil ? since : nil,
            modelContext: modelContext
        )
        var page = 1
        var after: String?

        while true {
            if let maxPages, page > maxPages {
                return false
            }

            try Task.checkCancellation()
            syncMessage = "\(phase) \(repository.fullName) page \(page)"

            let history = try await api.commitHistoryPage(
                owner: repository.ownerLogin,
                repo: repository.name,
                authorID: authorID,
                since: since,
                until: until,
                after: after,
                perPage: commitPageSize
            )

            let result = try upsertGraphQLCommits(
                history.commits,
                repository: repository,
                author: author,
                existingCommits: &existingCommits,
                modelContext: modelContext
            )
            importedCommitCount += result.inserted
            updatedDiffStatCount += result.updatedStats
            try modelContext.save()
            syncMessage = "\(phase) \(repository.fullName): \(importedCommitCount) new commits, \(updatedDiffStatCount) line stats"

            guard history.hasNextPage, let endCursor = history.endCursor else {
                return true
            }

            after = endCursor
            page += 1
        }
    }

    private func syncCommitPages(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        author: String,
        since: Date,
        until: Date?,
        phase: String,
        maxPages: Int? = nil,
        existingCommitIDs: inout Set<String>,
        modelContext: ModelContext
    ) async throws {
        var page = 1
        while true {
            if let maxPages, page > maxPages {
                return
            }
            try Task.checkCancellation()
            syncMessage = "\(phase) \(repository.fullName) page \(page)"

            let commits = try await api.commitPage(
                owner: repository.ownerLogin,
                repo: repository.name,
                author: author,
                since: since,
                until: until,
                page: page,
                perPage: commitPageSize
            )
            guard !commits.isEmpty else {
                return
            }

            let inserted = try upsertCommits(
                commits,
                repository: repository,
                author: author,
                existingCommitIDs: &existingCommitIDs,
                modelContext: modelContext
            )
            importedCommitCount += inserted
            try modelContext.save()
            syncMessage = "\(phase) \(repository.fullName): \(importedCommitCount) new commits"

            guard commits.count == commitPageSize else {
                return
            }
            page += 1
        }
    }

    private func backfillDiffStats(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        requestLimit: Int,
        authoredSince: Date? = nil,
        order: DiffStatsBackfillOrder = .newestFirst,
        modelContext: ModelContext
    ) async throws -> (attempted: Int, updated: Int) {
        guard requestLimit > 0 else {
            return (0, 0)
        }

        let candidates = try commitsNeedingDiffStats(
            repositoryFullName: repository.fullName,
            authoredSince: authoredSince,
            order: order,
            modelContext: modelContext
        )
        guard !candidates.isEmpty else {
            return (0, 0)
        }

        var attempted = 0
        var updated = 0
        for commit in candidates.prefix(requestLimit) {
            try Task.checkCancellation()
            attempted += 1
            syncMessage = "Fetching stats \(repository.fullName): \(attempted) of \(min(candidates.count, requestLimit))"

            do {
                let detail = try await api.commitDetail(
                    owner: repository.ownerLogin,
                    repo: repository.name,
                    sha: commit.sha
                )
                commit.applyDiffStats(from: detail)
                updated += 1
                updatedDiffStatCount += 1
            } catch {
                commit.markDiffStatsFailed(error.localizedDescription)
            }

            if attempted % 10 == 0 {
                try modelContext.save()
            }
        }

        if attempted > 0 {
            try modelContext.save()
        }
        return (attempted, updated)
    }

    private func commitsNeedingDiffStats(
        repositoryFullName: String,
        authoredSince: Date? = nil,
        order: DiffStatsBackfillOrder = .newestFirst,
        modelContext: ModelContext
    ) throws -> [GitCommitRecord] {
        let fullName = repositoryFullName
        let sortOrder: SortOrder = order == .newestFirst ? .reverse : .forward
        if let authoredSince {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt >= authoredSince },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            return try modelContext.fetch(descriptor).filter { $0.diffStatsFetchedAt == nil }
        } else {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            return try modelContext.fetch(descriptor).filter { $0.diffStatsFetchedAt == nil }
        }
    }

    private func missingDiffStatsWindow(
        repositoryFullName: String,
        since: Date,
        modelContext: ModelContext
    ) throws -> DateInterval? {
        let candidates = try commitsNeedingDiffStats(
            repositoryFullName: repositoryFullName,
            authoredSince: since,
            order: .newestFirst,
            modelContext: modelContext
        )
        guard let newestMissingDate = candidates.first?.authoredAt else {
            return nil
        }

        let oldestMissingDate = candidates.last?.authoredAt ?? newestMissingDate
        let start = max(oldestMissingDate.addingTimeInterval(-1), since)
        let end = newestMissingDate.addingTimeInterval(1)
        guard start < end else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func syncCompleteMessage(prefix: String = "Sync complete", failedRepositoryCount: Int) -> String {
        var parts = ["\(prefix): \(importedCommitCount) new commits"]
        if updatedDiffStatCount > 0 {
            parts.append("updated \(updatedDiffStatCount) diff stats")
        }
        if failedRepositoryCount > 0 {
            parts.append("\(failedRepositoryCount) repositories need another sync")
        }
        return parts.joined(separator: ". ")
    }

    private func todaySyncCompleteMessage(failedRepositoryCount: Int) -> String {
        var parts = ["Today refreshed: \(importedCommitCount) new commits"]
        if updatedDiffStatCount > 0 {
            parts.append("updated \(updatedDiffStatCount) diff stats")
        }
        if failedRepositoryCount > 0 {
            parts.append("\(failedRepositoryCount) repositories need full sync")
        }
        return parts.joined(separator: ". ")
    }

    private func existingCommitIDs(
        repositoryFullName: String,
        authoredSince: Date? = nil,
        modelContext: ModelContext
    ) throws -> Set<String> {
        let fullName = repositoryFullName
        if let authoredSince {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt >= authoredSince }
            )
            return Set(try modelContext.fetch(descriptor).map(\.id))
        } else {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName }
            )
            return Set(try modelContext.fetch(descriptor).map(\.id))
        }
    }

    private func existingCommitRecords(
        repositoryFullName: String,
        authoredSince: Date? = nil,
        modelContext: ModelContext
    ) throws -> [String: GitCommitRecord] {
        let fullName = repositoryFullName
        let records: [GitCommitRecord]
        if let authoredSince {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt >= authoredSince }
            )
            records = try modelContext.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName }
            )
            records = try modelContext.fetch(descriptor)
        }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    private func newestCommitDate(
        repositoryFullName: String,
        modelContext: ModelContext
    ) throws -> Date? {
        let fullName = repositoryFullName
        var descriptor = FetchDescriptor<GitCommitRecord>(
            predicate: #Predicate { $0.repositoryFullName == fullName },
            sortBy: [SortDescriptor(\.authoredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.authoredAt
    }

    private func oldestCommitDate(
        repositoryFullName: String,
        modelContext: ModelContext
    ) throws -> Date? {
        let fullName = repositoryFullName
        var descriptor = FetchDescriptor<GitCommitRecord>(
            predicate: #Predicate { $0.repositoryFullName == fullName },
            sortBy: [SortDescriptor(\.authoredAt)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.authoredAt
    }

    private func selectedRepositories(modelContext: ModelContext) throws -> [GitRepositoryRecord] {
        let descriptor = FetchDescriptor<GitRepositoryRecord>(
            predicate: #Predicate { $0.isSelected && $0.id > 0 },
            sortBy: [SortDescriptor(\.fullName)]
        )
        let selected = try modelContext.fetch(descriptor)
        guard let activeLogin = viewer?.login else {
            return selected
        }
        return selected.filter { $0.accountLogin == nil || $0.accountLogin == activeLogin }
    }

    private func commitExists(id: String, modelContext: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<GitCommitRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func demoRepository(modelContext: ModelContext) throws -> GitRepositoryRecord {
        let demoID: Int64 = -941
        var descriptor = FetchDescriptor<GitRepositoryRecord>(
            predicate: #Predicate { $0.id == demoID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let repo = GitRepositoryRecord(
            id: demoID,
            ownerLogin: "captains-log",
            name: "demo",
            fullName: "captains-log/demo",
            isPrivate: false,
            isSelected: true,
            htmlURL: URL(string: "https://github.com")
        )
        modelContext.insert(repo)
        return repo
    }

    private func deleteDemoData(modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<GitRepositoryRecord>(
            predicate: #Predicate { $0.id < 0 }
        )
        for repository in try modelContext.fetch(descriptor) {
            modelContext.delete(repository)
        }

        let summaries = try modelContext.fetch(FetchDescriptor<DailyJournalSummaryRecord>())
        for summary in summaries where summary.sourceCommitIDsBlob.contains("captains-log/demo#") {
            modelContext.delete(summary)
        }
    }

    private enum StorageError: LocalizedError {
        case missingModelContext

        var errorDescription: String? {
            "Local storage is not ready yet."
        }
    }
}
