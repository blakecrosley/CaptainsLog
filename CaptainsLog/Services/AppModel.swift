import Foundation
import OSLog
import SwiftData
import SwiftUI

enum RepositorySyncWindow {
    static func updateSince(
        fallbackSince: Date,
        lastSyncedAt: Date?,
        newestCommitDate: Date?,
        overlap: TimeInterval,
        minimumRescanSince: Date? = nil
    ) -> Date {
        guard newestCommitDate != nil else {
            return fallbackSince
        }

        let incrementalSince = [
            fallbackSince,
            lastSyncedAt?.addingTimeInterval(-overlap),
            newestCommitDate?.addingTimeInterval(-overlap)
        ]
        .compactMap { $0 }
        .max() ?? fallbackSince

        guard let minimumRescanSince else {
            return incrementalSince
        }

        return min(incrementalSince, max(fallbackSince, minimumRescanSince))
    }
}

enum RepositoryHistoryBackfillPolicy {
    static let fullSyncCommitPageLimit: Int? = nil
    static let indexPageBudgetPerRun = 500
}

enum RepositoryHotSyncPolicy {
    static let lookbackDays = 14
    static let minimumForegroundInterval: TimeInterval = 120
}

private enum DemoFixtureIdentity {
    static let login = "captains-log-demo"
    static let nodeID = "fixture-captains-log-demo"
    static let name = "Demo Developer"
    static let repositoryOwner = "captains-log-demo"
    static let repositoryName = "work-journal"
    static let repositoryFullName = "captains-log-demo/work-journal"
    static let url = URL(string: "https://github.com")!

    static let companionRepositories: [DemoFixtureRepository] = [
        DemoFixtureRepository(id: 941_001, name: "ios-client", isPrivate: true, isSelected: true, pushedDayOffset: 0),
        DemoFixtureRepository(id: 941_002, name: "metrics-lab", isPrivate: false, isSelected: true, pushedDayOffset: 1),
        DemoFixtureRepository(id: 941_003, name: "journal-prompts", isPrivate: true, isSelected: true, pushedDayOffset: 2),
        DemoFixtureRepository(id: 941_004, name: "docs-site", isPrivate: false, isSelected: false, pushedDayOffset: 5),
        DemoFixtureRepository(id: 941_005, name: "archive-tools", isPrivate: true, isSelected: false, pushedDayOffset: 12)
    ]
}

private struct DemoFixtureRepository {
    let id: Int64
    let name: String
    let isPrivate: Bool
    let isSelected: Bool
    let pushedDayOffset: Int
}

private enum DiffStatsBackfillOrder {
    case newestFirst
    case oldestFirst
}

private struct RepositorySyncResult {
    let updateSince: Date
    let usedHistoryStats: Bool
}

private struct HistoryBackfillStepResult {
    let pagesUsed: Int
    let completedMonth: Bool
    let completedRepository: Bool
    let hadWork: Bool
}

private struct HistoryPageSyncResult {
    let pagesUsed: Int
    let completed: Bool
    let updatedStats: Int
}

private struct MissingDiffStatsRepositoryPriority {
    let repository: GitRepositoryRecord
    let missingCount: Int
    let newestMissingAt: Date
}

struct LocalHistoryDeletionResult: Equatable {
    let deletedCommitCount: Int
    let deletedJournalCount: Int
    let resetRepositoryCount: Int

    var message: String {
        let commitWord = deletedCommitCount == 1 ? "commit" : "commits"
        let journalWord = deletedJournalCount == 1 ? "journal" : "journals"
        return "Cleared \(deletedCommitCount.formatted()) \(commitWord) and \(deletedJournalCount.formatted()) \(journalWord)."
    }
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
    private var oauthSession: GitHubOAuthSession?
    private var viewer: GitHubViewer?
    private var pendingDeviceCode: GitHubDeviceCodeResponse?
    private let syncLogger = Logger(subsystem: "com.blakecrosley.captainslog", category: "sync")
    private let performanceLogger = Logger(subsystem: "com.blakecrosley.captainslog", category: "performance")
    private let commitPageSize = 100
    private let commitSyncOverlap: TimeInterval = 300
    private let diffStatsBackfillPerRepositoryLimit = 100
    private let diffStatsBackfillPerSyncLimit = 300
    private let todayDiffStatsPerRepositoryLimit = 20
    private let todayDiffStatsPerSyncLimit = 80
    private let incrementalDiffStatsPerRepositoryLimit = 25
    private let incrementalDiffStatsPerSyncLimit = 100
    private let historicalBackfillCommitPagesPerRepository = RepositoryHistoryBackfillPolicy.fullSyncCommitPageLimit
    private let selectedPeriodDiffStatsPerRepositoryLimit = 250
    private let selectedPeriodDiffStatsPerSyncLimit = 1_000
    private let historicalBackfillPageBudgetPerRun = RepositoryHistoryBackfillPolicy.indexPageBudgetPerRun
    private let diffStatsRetryInterval: TimeInterval = 3_600
    private let missingDiffStatsPriorityFetchLimit = 80
    private let syncProgressPublishInterval: TimeInterval = 1.25
    private let syncSaveInterval: TimeInterval = 1.75
    private let syncSaveOperationLimit = 5
    private let syncUIPacingDelay: UInt64 = 20_000_000
    private var lastSyncProgressPublishedAt = Date.distantPast
    private var lastSyncSaveAt = Date.distantPast
    private var pendingSyncSaveOperationCount = 0
    private var pendingImportedCommitCount = 0
    private var pendingUpdatedDiffStatCount = 0

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
            guard let savedSession = try KeychainTokenStore.readSession() else {
                syncLogger.info("No saved GitHub token found during session load")
                authState = .signedOut
                return
            }
            let validSession = try await refreshSessionIfNeeded(savedSession, login: nil)
            oauthSession = validSession
            token = validSession.accessToken
            let loadedViewer = try await GitHubAPIClient(token: validSession.accessToken, appSlug: githubAppSlug).viewer()
            viewer = loadedViewer
            if let modelContext {
                try deleteDemoData(modelContext: modelContext)
                try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
                try modelContext.save()
            }
            try KeychainTokenStore.saveSession(validSession, login: loadedViewer.login)
            authState = .signedIn(loadedViewer)
            syncLogger.info("Loaded GitHub session for \(loadedViewer.login, privacy: .public)")
        } catch {
            if handleExpiredGitHubSessionError(error, operation: "Load GitHub session") {
                return
            }
            oauthSession = nil
            token = nil
            viewer = nil
            authState = .failed(error.localizedDescription)
            syncLogger.error("Failed to load GitHub session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restoreSessionForSyncIfNeeded() async -> Bool {
        if let currentSession = oauthSession, let currentViewer = viewer {
            do {
                let validSession = try await refreshSessionIfNeeded(currentSession, login: currentViewer.login)
                oauthSession = validSession
                token = validSession.accessToken
                return true
            } catch {
                return !handleExpiredGitHubSessionError(error, operation: "Refresh GitHub session", login: currentViewer.login)
            }
        }

        syncMessage = "Restoring GitHub session"
        syncLogger.info("Sync requested without an in-memory GitHub session; restoring from keychain")

        do {
            guard let savedSession = try KeychainTokenStore.readSession() else {
                syncMessage = "Sign in to GitHub again"
                authState = .signedOut
                syncLogger.error("No saved GitHub token available for sync")
                return false
            }

            let validSession = try await refreshSessionIfNeeded(savedSession, login: nil)
            oauthSession = validSession
            token = validSession.accessToken
            let loadedViewer = try await GitHubAPIClient(token: validSession.accessToken, appSlug: githubAppSlug).viewer()
            viewer = loadedViewer

            if let modelContext {
                try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
                try modelContext.save()
            }

            try KeychainTokenStore.saveSession(validSession, login: loadedViewer.login)
            authState = .signedIn(loadedViewer)
            syncLogger.info("Restored GitHub session for \(loadedViewer.login, privacy: .public)")
            return true
        } catch {
            if handleExpiredGitHubSessionError(error, operation: "Restore GitHub session") {
                return false
            }
            oauthSession = nil
            token = nil
            viewer = nil
            syncMessage = "GitHub session failed: \(error.localizedDescription)"
            authState = .failed(error.localizedDescription)
            syncLogger.error("Failed to restore GitHub session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func refreshSessionIfNeeded(
        _ session: GitHubOAuthSession,
        login: String?
    ) async throws -> GitHubOAuthSession {
        guard session.shouldRefresh() else {
            return session
        }
        guard let refreshToken = session.refreshToken else {
            return session
        }

        syncMessage = "Refreshing GitHub session"
        let refreshedSession = try await GitHubDeviceAuthService(clientID: githubClientID)
            .refreshSession(refreshToken: refreshToken)
        if let login {
            try KeychainTokenStore.saveSession(refreshedSession, login: login)
        }
        syncLogger.info("Refreshed GitHub session token")
        return refreshedSession
    }

    private func handleExpiredGitHubSessionError(
        _ error: Error,
        operation: String,
        login: String? = nil
    ) -> Bool {
        if handleUnauthorizedGitHubError(error, operation: operation, login: login) {
            return true
        }
        guard let githubError = error as? GitHubError, githubError.isRefreshTokenInvalid else {
            return false
        }
        expireGitHubSession(operation: operation, login: login)
        return true
    }

    private func handleUnauthorizedGitHubError(
        _ error: Error,
        operation: String,
        login: String? = nil
    ) -> Bool {
        guard let githubError = error as? GitHubError, githubError.isUnauthorized else {
            return false
        }
        expireGitHubSession(operation: operation, login: login)
        return true
    }

    private func expireGitHubSession(operation: String, login: String?) {
        let invalidLogin = login ?? viewer?.login
        if let invalidLogin {
            try? KeychainTokenStore.deleteToken(login: invalidLogin)
        } else {
            try? KeychainTokenStore.deleteToken()
        }

        oauthSession = nil
        token = nil
        viewer = nil
        pendingDeviceCode = nil
        repositoryApprovalURL = githubAppInstallURL

        let message = "GitHub session expired. Sign in again."
        syncMessage = message
        authMessage = message
        authState = .signedOut
        syncLogger.error("\(operation, privacy: .public) failed because GitHub rejected the saved session")
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
            guard let session = try await auth.exchangeDeviceSession(deviceCode: code.deviceCode) else {
                authState = .waitingForUser(code)
                authMessage = "GitHub has not confirmed this code yet."
                return
            }
            let loadedViewer = try await GitHubAPIClient(token: session.accessToken, appSlug: githubAppSlug).viewer()
            try KeychainTokenStore.saveSession(session, login: loadedViewer.login)
            oauthSession = session
            token = session.accessToken
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
        oauthSession = nil
        token = nil
        viewer = nil
        pendingDeviceCode = nil
        authMessage = ""
        repositoryApprovalURL = githubAppInstallURL
        authState = .signedOut
    }

    @discardableResult
    func clearImportedHistory() throws -> LocalHistoryDeletionResult {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }
        guard !isSyncing else {
            throw StorageError.syncInProgress
        }

        BackgroundHistoryIndexer.cancelPending()

        let commits = try modelContext.fetch(FetchDescriptor<GitCommitRecord>())
        let summaries = try modelContext.fetch(FetchDescriptor<DailyJournalSummaryRecord>())
        let repositories = try modelContext.fetch(FetchDescriptor<GitRepositoryRecord>())

        for commit in commits {
            modelContext.delete(commit)
        }
        for summary in summaries {
            modelContext.delete(summary)
        }
        for repository in repositories {
            repository.resetImportedHistoryState()
        }

        try modelContext.save()
        resetSyncProgress()

        let result = LocalHistoryDeletionResult(
            deletedCommitCount: commits.count,
            deletedJournalCount: summaries.count,
            resetRepositoryCount: repositories.count
        )
        syncMessage = result.message
        syncLogger.info("Cleared imported history: \(commits.count, privacy: .public) commits, \(summaries.count, privacy: .public) journals, \(repositories.count, privacy: .public) repositories reset")
        return result
    }

    func switchAccount(_ account: GitHubAccountRecord) async {
        guard let modelContext else {
            authState = .failed(StorageError.missingModelContext.localizedDescription)
            return
        }

        do {
            guard let savedSession = try KeychainTokenStore.readSession(login: account.login) else {
                authState = .failed("Sign in to @\(account.login) again.")
                return
            }
            let validSession = try await refreshSessionIfNeeded(savedSession, login: account.login)
            let loadedViewer = try await GitHubAPIClient(token: validSession.accessToken, appSlug: githubAppSlug).viewer()
            try KeychainTokenStore.saveActiveLogin(loadedViewer.login)
            oauthSession = validSession
            token = validSession.accessToken
            viewer = loadedViewer
            try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
            try modelContext.save()
            authState = .signedIn(loadedViewer)
        } catch {
            if handleExpiredGitHubSessionError(error, operation: "Switch GitHub account", login: account.login) {
                return
            }
            authState = .failed(error.localizedDescription)
        }
    }

    func refreshRepositories() async {
        syncLogger.info("Refresh repositories requested")
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Refresh repositories ignored because sync is already running")
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Refresh repositories failed: missing model context")
            return
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Refresh repositories failed: no GitHub session")
            return
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Refresh repositories failed: token is nil after restore")
            return
        }

        isSyncing = true
        syncMessage = "Loading repositories"
        defer { isSyncing = false }

        do {
            let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
            let access = try await updateRepositoryAccess(api: api, modelContext: modelContext)
            if !access.canReadContents {
                syncMessage = "Set Contents to read-only in the GitHub App permissions, then approve repository access."
            } else if access.repositories.isEmpty {
                syncMessage = "Approve access to all repositories or selected repositories in GitHub."
            } else {
                syncMessage = "Loaded \(access.repositories.count) repositories"
            }
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Refresh repositories") {
                return
            }
            syncMessage = error.localizedDescription
        }
    }

    @discardableResult
    func syncSelectedRepositories(
        lookbackDays: Int = 370,
        repositoryIDs: Set<Int64>? = nil,
        forceLookbackWindow: Bool = false
    ) async -> Bool {
        syncLogger.info("Sync updates requested")
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Sync updates ignored because sync is already running")
            return false
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Sync updates failed: missing model context")
            return false
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Sync updates failed: no GitHub session")
            return false
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Sync updates failed: token nil after restore")
            return false
        }

        isSyncing = true
        resetSyncProgress()
        syncMessage = "Syncing updates"
        defer { finishSyncProgress() }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        let fallbackSince = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        var failedRepositories: [(name: String, message: String)] = []

        do {
            let selected = recentSyncPriority(
                try selectedRepositories(modelContext: modelContext)
                    .filter { repository in
                        guard let repositoryIDs else {
                            return true
                        }
                        return repositoryIDs.contains(repository.id)
                    }
            )
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return false
            }

            var diffStatsBudget = incrementalDiffStatsPerSyncLimit
            for repository in selected {
                do {
                    let syncResult = try await syncRepositoryCommits(
                        repository,
                        api: api,
                        fallbackSince: fallbackSince,
                        minimumRescanSince: forceLookbackWindow ? fallbackSince : nil,
                        phase: "Syncing updates",
                        backfillHistoricalGaps: false,
                        modelContext: modelContext
                    )
                    if diffStatsBudget > 0 {
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
                    try? await flushSyncBatch(modelContext: modelContext)
                    syncMessage = "Sync canceled"
                    return false
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Sync updates") {
                        return false
                    }
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            try await flushSyncBatch(modelContext: modelContext)
            let changed = hasPendingSyncWork
            if failedRepositories.isEmpty {
                syncMessage = syncCompleteMessage(failedRepositoryCount: 0)
            } else if hasPendingSyncWork {
                syncMessage = syncCompleteMessage(failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Sync failed"
            }
            return changed
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Sync updates") {
                return false
            }
            syncMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func syncLatestIfStale(
        minimumInterval: TimeInterval = RepositoryHotSyncPolicy.minimumForegroundInterval,
        lookbackDays: Int = RepositoryHotSyncPolicy.lookbackDays
    ) async -> Bool {
        syncLogger.info("Latest commit sync check requested")
        guard !isSyncing else {
            syncLogger.info("Latest commit sync skipped because sync is already running")
            return false
        }
        guard let modelContext else {
            syncLogger.error("Latest commit sync failed: missing model context")
            return false
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Latest commit sync failed: no GitHub session")
            return false
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Latest commit sync failed: token nil after restore")
            return false
        }

        do {
            let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
            do {
                _ = try await updateRepositoryAccess(api: api, modelContext: modelContext)
            } catch {
                if handleUnauthorizedGitHubError(error, operation: "Latest commit repository refresh") {
                    return false
                }
                syncLogger.warning("Latest commit sync continued without fresh repository metadata: \(error.localizedDescription, privacy: .public)")
            }

            let selected = try selectedRepositories(modelContext: modelContext)
                .filter(\.isGitHubBacked)
            guard !selected.isEmpty else {
                syncLogger.info("Latest commit sync skipped because no GitHub repositories are selected")
                return false
            }

            let now = Date()
            let staleRepositories = selected.filter { repository in
                guard let lastSyncedAt = repository.lastSyncedAt else {
                    return true
                }
                if let pushedAt = repository.pushedAt,
                   pushedAt > lastSyncedAt.addingTimeInterval(-commitSyncOverlap) {
                    return true
                }
                return now.timeIntervalSince(lastSyncedAt) >= minimumInterval
            }

            guard !staleRepositories.isEmpty else {
                syncLogger.info("Latest commit sync skipped because selected repositories are fresh")
                return false
            }
            syncLogger.info("Latest commit sync will scan \(staleRepositories.count) stale repositories")
            return await syncSelectedRepositories(
                lookbackDays: lookbackDays,
                repositoryIDs: Set(staleRepositories.map(\.id)),
                forceLookbackWindow: true
            )
        } catch {
            syncLogger.error("Latest commit sync failed while checking selected repositories: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func backfillSelectedPeriodLineStats(
        scope: WorkRangeScope,
        interval: DateInterval
    ) async {
        syncLogger.info("Selected period line stats requested: \(scope.rawValue)")
        guard interval.start < interval.end else {
            syncMessage = "Choose a valid period"
            return
        }
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Selected period line stats ignored because sync is already running")
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Selected period line stats failed: missing model context")
            return
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Selected period line stats failed: no GitHub session")
            return
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Selected period line stats failed: token nil after restore")
            return
        }

        isSyncing = true
        resetSyncProgress()
        syncMessage = "Filling \(scope.syncTitle) line stats"
        defer { finishSyncProgress() }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        var failedRepositories: [(name: String, message: String)] = []
        var diffStatsBudget = selectedPeriodDiffStatsPerSyncLimit

        do {
            let selected = try selectedRepositories(modelContext: modelContext)
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return
            }

            for repository in selected {
                do {
                    let usedHistoryStats = try await syncCommitHistoryPagesIfAvailable(
                        repository,
                        api: api,
                        since: interval.start,
                        until: interval.end,
                        phase: "Filling \(scope.title) lines",
                        maxPages: nil,
                        modelContext: modelContext
                    )

                    if !usedHistoryStats {
                        var fallbackCommitIDs = try existingCommitIDs(
                            repositoryFullName: repository.fullName,
                            authoredSince: interval.start,
                            modelContext: modelContext
                        )
                        try await syncCommitPages(
                            repository,
                            api: api,
                            since: interval.start,
                            until: interval.end,
                            phase: "Filling \(scope.title) commits",
                            existingCommitIDs: &fallbackCommitIDs,
                            modelContext: modelContext
                        )
                    }

                    if diffStatsBudget > 0 {
                        let result = try await backfillDiffStats(
                            repository,
                            api: api,
                            requestLimit: min(selectedPeriodDiffStatsPerRepositoryLimit, diffStatsBudget),
                            authoredSince: interval.start,
                            authoredBefore: interval.end,
                            order: .newestFirst,
                            modelContext: modelContext
                        )
                        diffStatsBudget -= result.attempted
                    }
                } catch is CancellationError {
                    try? await flushSyncBatch(modelContext: modelContext)
                    syncMessage = "Line stats fill canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Selected period line stats") {
                        return
                    }
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            try await flushSyncBatch(modelContext: modelContext)
            if failedRepositories.isEmpty {
                if diffStatsBudget == 0 {
                    syncMessage = "Filled \(pendingUpdatedDiffStatCount.formatted()) line stats; run again for more"
                } else if !hasPendingSyncWork {
                    syncMessage = "Line stats already complete for selected \(scope.syncTitle)"
                } else {
                    syncMessage = syncCompleteMessage(prefix: "Line stats filled", failedRepositoryCount: 0)
                }
            } else if hasPendingSyncWork {
                syncMessage = syncCompleteMessage(prefix: "Line stats filled", failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Line stats fill failed"
            }
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Selected period line stats") {
                return
            }
            syncMessage = error.localizedDescription
        }
    }

    func fullSyncSelectedRepositories(
        lookbackDays: Int = 7_300
    ) async {
        syncLogger.info("Historical analytics index requested")
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Historical analytics index ignored because sync is already running")
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Historical analytics index failed: missing model context")
            return
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Historical analytics index failed: no GitHub session")
            return
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Historical analytics index failed: token nil after restore")
            return
        }

        isSyncing = true
        resetSyncProgress()
        syncMessage = "Indexing historical analytics"
        defer { finishSyncProgress() }

        let api = GitHubAPIClient(token: token, appSlug: githubAppSlug)
        let lowerBound = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        var failedRepositories: [(name: String, message: String)] = []
        var pageBudget = historicalBackfillPageBudgetPerRun
        var completedMonths = 0
        var completedRepositories = 0
        var touchedRepositories = 0

        do {
            let selected = try selectedRepositories(modelContext: modelContext)
            guard !selected.isEmpty else {
                syncMessage = "Select at least one repository"
                return
            }

            var touchedRepositoryNames: Set<String> = []
            var failedRepositoryNames: Set<String> = []
            while pageBudget > 0 {
                var madeProgress = false
                let missingStatPriorities = try missingDiffStatsPriority(
                    selected,
                    since: lowerBound,
                    modelContext: modelContext
                )

                if !missingStatPriorities.isEmpty {
                    for priority in missingStatPriorities where !failedRepositoryNames.contains(priority.repository.fullName) {
                        guard pageBudget > 0 else {
                            break
                        }

                        do {
                            let result = try await backfillNextMissingDiffStatsMonth(
                                priority.repository,
                                api: api,
                                lowerBound: lowerBound,
                                pageBudget: &pageBudget,
                                modelContext: modelContext
                            )
                            if result.hadWork {
                                madeProgress = true
                                touchedRepositoryNames.insert(priority.repository.fullName)
                            }
                            if result.completedMonth {
                                completedMonths += 1
                            }
                        } catch is CancellationError {
                            try? await flushSyncBatch(modelContext: modelContext)
                            syncMessage = "Historical index canceled"
                            return
                        } catch {
                            if handleUnauthorizedGitHubError(error, operation: "Historical analytics index") {
                                return
                            }
                            failedRepositoryNames.insert(priority.repository.fullName)
                            priority.repository.markHistoryBackfillFailed(error.localizedDescription)
                            try? modelContext.save()
                            failedRepositories.append((priority.repository.fullName, error.localizedDescription))
                        }
                    }

                    guard madeProgress else {
                        break
                    }
                    continue
                }

                for repository in historyBackfillPriority(selected) where !failedRepositoryNames.contains(repository.fullName) {
                    guard pageBudget > 0 else {
                        break
                    }

                    do {
                        let result = try await backfillNextHistoryMonth(
                            repository,
                            api: api,
                            lowerBound: lowerBound,
                            pageBudget: &pageBudget,
                            modelContext: modelContext
                        )
                        if result.hadWork {
                            madeProgress = true
                            touchedRepositoryNames.insert(repository.fullName)
                        }
                        if result.completedMonth {
                            completedMonths += 1
                        }
                        if result.completedRepository {
                            completedRepositories += 1
                        }
                    } catch is CancellationError {
                        try? await flushSyncBatch(modelContext: modelContext)
                        syncMessage = "Historical index canceled"
                        return
                    } catch {
                        if handleUnauthorizedGitHubError(error, operation: "Historical analytics index") {
                            return
                        }
                        failedRepositoryNames.insert(repository.fullName)
                        repository.markHistoryBackfillFailed(error.localizedDescription)
                        try? modelContext.save()
                        failedRepositories.append((repository.fullName, error.localizedDescription))
                    }
                }

                guard madeProgress else {
                    break
                }
            }
            touchedRepositories = touchedRepositoryNames.count

            try await flushSyncBatch(modelContext: modelContext)
            if failedRepositories.isEmpty {
                syncMessage = historyIndexCompleteMessage(
                    completedMonths: completedMonths,
                    completedRepositories: completedRepositories,
                    touchedRepositories: touchedRepositories,
                    pageBudgetExhausted: pageBudget == 0,
                    failedRepositoryCount: 0
                )
            } else if hasPendingSyncWork {
                syncMessage = historyIndexCompleteMessage(
                    completedMonths: completedMonths,
                    completedRepositories: completedRepositories,
                    touchedRepositories: touchedRepositories,
                    pageBudgetExhausted: pageBudget == 0,
                    failedRepositoryCount: failedRepositories.count
                )
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Historical index failed"
            }
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Historical analytics index") {
                return
            }
            syncMessage = error.localizedDescription
        }
    }

    func hasHistoricalAnalyticsBackfillWork(
        lookbackDays: Int = 7_300
    ) throws -> Bool {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }

        let lowerBound = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let selected = try selectedRepositories(modelContext: modelContext)
            .filter(\.isGitHubBacked)

        guard !selected.isEmpty else {
            return false
        }

        if try !missingDiffStatsPriority(
            selected,
            since: lowerBound,
            modelContext: modelContext
        ).isEmpty {
            return true
        }

        return selected.contains { repository in
            guard repository.isHistoryBackfillComplete else {
                return true
            }
            guard let completedLowerBound = repository.historyBackfillLowerBound else {
                return true
            }
            return completedLowerBound > lowerBound
        }
    }

    func syncToday() async {
        syncLogger.info("Refresh today requested")
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Refresh today ignored because sync is already running")
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Refresh today failed: missing model context")
            return
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Refresh today failed: no GitHub session")
            return
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Refresh today failed: token nil after restore")
            return
        }

        isSyncing = true
        resetSyncProgress()
        syncMessage = "Refreshing today"
        defer { finishSyncProgress() }

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
                        fallbackSince: startOfToday,
                        minimumRescanSince: startOfToday,
                        phase: "Refreshing today",
                        backfillHistoricalGaps: false,
                        modelContext: modelContext
                    )
                    if diffStatsBudget > 0 {
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
                    try? await flushSyncBatch(modelContext: modelContext)
                    syncMessage = "Refresh canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Refresh today") {
                        return
                    }
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            try await flushSyncBatch(modelContext: modelContext)
            if failedRepositories.isEmpty {
                syncMessage = todaySyncCompleteMessage(failedRepositoryCount: 0)
            } else if hasPendingSyncWork {
                syncMessage = todaySyncCompleteMessage(failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Refresh failed"
            }
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Refresh today") {
                return
            }
            syncMessage = error.localizedDescription
        }
    }

    func seedDemoData(includeFixtureDetails: Bool = false) throws {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }

        let repo = try demoRepository(modelContext: modelContext, includeFixtureDetails: includeFixtureDetails)
        if includeFixtureDetails {
            try seedFixtureRepositoryList(modelContext: modelContext)

            let demoViewer = GitHubViewer(
                login: DemoFixtureIdentity.login,
                nodeID: DemoFixtureIdentity.nodeID,
                name: DemoFixtureIdentity.name,
                avatarURL: nil,
                htmlURL: DemoFixtureIdentity.url
            )
            try upsertAccount(demoViewer, isActive: true, modelContext: modelContext)
            let session = GitHubOAuthSession(accessToken: "captains-log-fixture-token")
            token = session.accessToken
            oauthSession = session
            viewer = demoViewer
            authState = .signedIn(demoViewer)

            repo.lastSyncedAt = Date()
            repo.pushedAt = Date()
            repo.historyBackfillCompletedAt = Date()
            repo.historyBackfillLowerBound = Calendar.current.date(byAdding: .year, value: -1, to: Date())
            repo.historyBackfillLastError = nil
        }

        let calendar = Calendar.current
        let subjects = [
            "Add GitHub device auth shell",
            "Build contribution heatmap",
            "Port week calendar from Reps",
            "Draft Foundation Models journal prompt",
            "Tighten repository picker empty state",
            "Store summary source commit IDs"
        ]

        let recentOffsets = (0..<18).filter { $0 % 3 != 1 }
        let yearOffsets = includeFixtureDetails
            ? [
                24, 31, 45, 58, 73, 84,
                97, 112, 126, 139, 154, 168,
                183, 197, 212, 229, 244, 259,
                276, 291, 307, 322, 339, 356
            ]
            : []
        let demoDayOffsets = recentOffsets + yearOffsets

        for offset in demoDayOffsets {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                continue
            }

            let commitsForDay = (offset % 4) + 1
            for index in 0..<commitsForDay {
                let sha = "demo\(offset)\(index)00000000000000000000000000000000000"
                let id = "\(repo.fullName)#\(sha)"
                let record: GitCommitRecord
                if let existing = try fetchCommit(id: id, modelContext: modelContext) {
                    record = existing
                } else {
                    record = GitCommitRecord(
                        sha: sha,
                        repositoryFullName: repo.fullName,
                        authorLogin: includeFixtureDetails ? DemoFixtureIdentity.login : "demo",
                        message: subjects[(offset + index) % subjects.count],
                        authoredAt: calendar.date(byAdding: .hour, value: index + 9, to: calendar.startOfDay(for: date)) ?? date,
                        htmlURL: URL(string: "https://github.com/captains-log/demo/commit/\(sha)")
                    )
                    modelContext.insert(record)
                }
                record.repository = repo
                if includeFixtureDetails {
                    let additions = (offset + 1) * (index + 4) * 7
                    let deletions = (offset % 5 + 1) * (index + 1) * 3
                    record.applyDiffStats(additions: additions, deletions: deletions, changedFileCount: index + 2)
                    let demoFiles = [
                        "CaptainsLog/Views/WorkOverviewView.swift",
                        "CaptainsLog/Services/AppModel.swift",
                        "CaptainsLogTests/CalendarMathTests.swift"
                    ]
                    record.changedFiles = Array(demoFiles.prefix(index + 2))
                }
            }
        }

        if includeFixtureDetails {
            try seedDemoSummary(modelContext: modelContext, repo: repo, calendar: calendar)
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
            guard existing.update(from: draft, sourceCommitIDs: sourceCommitIDs, modelName: modelName) else {
                throw StorageError.lockedSummary
            }
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

    func toggleSummaryLock(date: Date) throws {
        guard let modelContext else {
            throw StorageError.missingModelContext
        }

        let dayKey = GitCommitRecord.dayKey(for: date)
        var descriptor = FetchDescriptor<DailyJournalSummaryRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        descriptor.fetchLimit = 1

        guard let summary = try modelContext.fetch(descriptor).first else {
            return
        }

        summary.isLocked.toggle()
        try modelContext.save()
    }

    private func updateRepositoryAccess(
        api: GitHubAPIClient,
        modelContext: ModelContext
    ) async throws -> GitHubRepositoryAccess {
        let access = try await api.repositoryAccess()
        repositoryApprovalURL = access.approvalURL ?? githubAppInstallURL
        try deleteDemoData(modelContext: modelContext)
        try upsertRepositories(access.repositories, accountLogin: viewer?.login, modelContext: modelContext)
        return access
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
                authorLogin: remote.author?.login,
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
                    authorLogin: remote.authorLogin,
                    message: remote.message,
                    authoredAt: remote.authoredDate,
                    htmlURL: remote.url
                )
                record.repository = repository
                modelContext.insert(record)
                existingCommits[id] = record
                inserted += 1
            }

            guard let additions = remote.additions,
                  let deletions = remote.deletions else {
                continue
            }
            let changedFileCount = remote.changedFilesIfAvailable ?? 0
            if record.additions != remote.additions ||
                record.deletions != remote.deletions ||
                record.changedFileCount != changedFileCount {
                record.applyDiffStats(
                    additions: additions,
                    deletions: deletions,
                    changedFileCount: changedFileCount
                )
                updatedStats += 1
            }
        }

        return (inserted, updatedStats)
    }

    private func backfillNextHistoryMonth(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        lowerBound: Date,
        pageBudget: inout Int,
        modelContext: ModelContext
    ) async throws -> HistoryBackfillStepResult {
        guard pageBudget > 0 else {
            return HistoryBackfillStepResult(pagesUsed: 0, completedMonth: false, completedRepository: false, hadWork: false)
        }
        guard let interval = try currentOrNextHistoryBackfillInterval(
            for: repository,
            lowerBound: lowerBound,
            modelContext: modelContext
        ) else {
            return HistoryBackfillStepResult(
                pagesUsed: 0,
                completedMonth: false,
                completedRepository: repository.isHistoryBackfillComplete,
                hadWork: false
            )
        }

        let startingCursor = repository.historyBackfillPageCursor
        repository.markHistoryBackfillMonth(interval, pageCursor: startingCursor)
        try await saveSyncBatch(modelContext: modelContext)

        var existingCommits = try existingCommitRecords(
            repositoryFullName: repository.fullName,
            authoredSince: interval.start,
            authoredBefore: interval.end,
            modelContext: modelContext
        )
        var after = startingCursor
        var pagesUsed = 0
        var unpersistedPageCursor = startingCursor

        while pageBudget > 0 {
            try Task.checkCancellation()
            let monthLabel = interval.start.formatted(.dateTime.month(.abbreviated).year())
            await publishSyncProgress("Indexing \(repository.fullName) \(monthLabel)")

            let history = try await api.commitHistoryPage(
                owner: repository.ownerLogin,
                repo: repository.name,
                since: interval.start,
                until: interval.end,
                after: after,
                perPage: commitPageSize
            )
            pagesUsed += 1
            pageBudget -= 1

            let upsertStart = Date()
            let result = try upsertGraphQLCommits(
                history.commits,
                repository: repository,
                existingCommits: &existingCommits,
                modelContext: modelContext
            )
            logSlowSyncOperation(
                "History backfill GraphQL upsert \(repository.fullName) page \(pagesUsed.formatted()) with \(history.commits.count.formatted()) commits",
                startedAt: upsertStart,
                threshold: 0.05
            )
            recordSyncProgress(insertedCommits: result.inserted, updatedDiffStats: result.updatedStats)
            repository.recordHistoryBackfillProgress(
                processedCommits: history.commits.count,
                updatedStats: result.updatedStats
            )

            guard history.hasNextPage else {
                let nextCursor = HistoryBackfillPlanner.nextCursor(afterCompleted: interval)
                let completedRepository = HistoryBackfillPlanner.isComplete(
                    afterCompleted: interval,
                    lowerBound: lowerBound
                )
                repository.advanceHistoryBackfillCursor(
                    to: nextCursor,
                    completedAt: completedRepository ? Date() : nil
                )
                try await saveSyncBatch(modelContext: modelContext)
                return HistoryBackfillStepResult(
                    pagesUsed: pagesUsed,
                    completedMonth: true,
                    completedRepository: completedRepository,
                    hadWork: true
                )
            }

            guard let endCursor = history.endCursor else {
                throw GitHubError.invalidResponse
            }
            after = endCursor
            unpersistedPageCursor = endCursor
            if pagesUsed.isMultiple(of: syncSaveOperationLimit) {
                repository.historyBackfillPageCursor = unpersistedPageCursor
                repository.historyBackfillLastAttemptAt = Date()
                repository.historyBackfillLastError = nil
                try await saveSyncBatch(modelContext: modelContext)
            } else {
                await Task.yield()
            }
        }

        repository.historyBackfillPageCursor = unpersistedPageCursor
        repository.historyBackfillLastAttemptAt = Date()
        repository.historyBackfillLastError = nil
        try await flushSyncBatch(modelContext: modelContext)
        return HistoryBackfillStepResult(
            pagesUsed: pagesUsed,
            completedMonth: false,
            completedRepository: false,
            hadWork: pagesUsed > 0
        )
    }

    private func backfillNextMissingDiffStatsMonth(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        lowerBound: Date,
        pageBudget: inout Int,
        modelContext: ModelContext
    ) async throws -> HistoryBackfillStepResult {
        guard pageBudget > 0 else {
            return HistoryBackfillStepResult(pagesUsed: 0, completedMonth: false, completedRepository: false, hadWork: false)
        }
        guard let interval = try missingDiffStatsMonthInterval(
            repositoryFullName: repository.fullName,
            since: lowerBound,
            modelContext: modelContext
        ) else {
            return HistoryBackfillStepResult(pagesUsed: 0, completedMonth: false, completedRepository: false, hadWork: false)
        }

        let result = try await syncCommitHistoryPagesWithBudget(
            repository,
            api: api,
            since: interval.start,
            until: interval.end,
            phase: "Indexing line stats",
            pageBudget: &pageBudget,
            modelContext: modelContext
        )

        return HistoryBackfillStepResult(
            pagesUsed: result.pagesUsed,
            completedMonth: result.completed,
            completedRepository: false,
            hadWork: result.pagesUsed > 0
        )
    }

    private func currentOrNextHistoryBackfillInterval(
        for repository: GitRepositoryRecord,
        lowerBound: Date,
        modelContext: ModelContext
    ) throws -> DateInterval? {
        repository.prepareHistoryBackfill(lowerBound: lowerBound)

        if let monthStart = repository.historyBackfillMonthStart,
           let monthEnd = repository.historyBackfillMonthEnd,
           monthStart < monthEnd {
            return DateInterval(start: monthStart, end: monthEnd)
        }

        if repository.isHistoryBackfillComplete,
           let existingLowerBound = repository.historyBackfillLowerBound,
           existingLowerBound <= lowerBound {
            return nil
        }

        let newestLocalCommitDate = try newestCommitDate(
            repositoryFullName: repository.fullName,
            modelContext: modelContext
        )
        let anchorDate = [
            repository.pushedAt,
            newestLocalCommitDate
        ]
        .compactMap { $0 }
        .max() ?? Date()

        guard let interval = HistoryBackfillPlanner.monthInterval(
            cursorDate: repository.historyBackfillCursorDate,
            anchorDate: anchorDate,
            lowerBound: lowerBound
        ) else {
            repository.advanceHistoryBackfillCursor(to: lowerBound, completedAt: Date())
            try modelContext.save()
            return nil
        }

        return interval
    }

    private func historyBackfillPriority(_ repositories: [GitRepositoryRecord]) -> [GitRepositoryRecord] {
        repositories.sorted { lhs, rhs in
            let lhsActive = lhs.historyBackfillMonthStart != nil
            let rhsActive = rhs.historyBackfillMonthStart != nil
            if lhsActive != rhsActive {
                return lhsActive
            }

            if lhs.isHistoryBackfillComplete != rhs.isHistoryBackfillComplete {
                return !lhs.isHistoryBackfillComplete
            }

            let lhsActivityDate = lhs.pushedAt ?? lhs.lastSyncedAt ?? lhs.createdAt
            let rhsActivityDate = rhs.pushedAt ?? rhs.lastSyncedAt ?? rhs.createdAt
            if lhsActivityDate != rhsActivityDate {
                return lhsActivityDate > rhsActivityDate
            }

            return lhs.fullName.localizedStandardCompare(rhs.fullName) == .orderedAscending
        }
    }

    private func recentSyncPriority(_ repositories: [GitRepositoryRecord]) -> [GitRepositoryRecord] {
        repositories.sorted { lhs, rhs in
            let lhsActivityDate = lhs.pushedAt ?? lhs.lastSyncedAt ?? lhs.createdAt
            let rhsActivityDate = rhs.pushedAt ?? rhs.lastSyncedAt ?? rhs.createdAt
            if lhsActivityDate != rhsActivityDate {
                return lhsActivityDate > rhsActivityDate
            }

            return lhs.fullName.localizedStandardCompare(rhs.fullName) == .orderedAscending
        }
    }

    private func missingDiffStatsPriority(
        _ repositories: [GitRepositoryRecord],
        since: Date,
        modelContext: ModelContext
    ) throws -> [MissingDiffStatsRepositoryPriority] {
        let scanStart = Date()
        let priorities: [MissingDiffStatsRepositoryPriority] = try repositories.compactMap { repository -> MissingDiffStatsRepositoryPriority? in
            let repositoryScanStart = Date()
            let candidates = try commitsNeedingDiffStats(
                repositoryFullName: repository.fullName,
                authoredSince: since,
                order: .newestFirst,
                fetchLimit: missingDiffStatsPriorityFetchLimit,
                modelContext: modelContext
            )
            logSlowSyncOperation(
                "missing diff stat priority scan \(repository.fullName) fetched \(candidates.count.formatted()) candidates",
                startedAt: repositoryScanStart,
                threshold: 0.08
            )
            guard let newestMissingAt = candidates.first?.authoredAt else {
                return nil
            }
            return MissingDiffStatsRepositoryPriority(
                repository: repository,
                missingCount: candidates.count,
                newestMissingAt: newestMissingAt
            )
        }

        logSlowSyncOperation(
            "missing diff stat priority scan across \(repositories.count.formatted()) repositories",
            startedAt: scanStart,
            threshold: 0.16
        )

        return priorities.sorted { lhs, rhs in
            if lhs.missingCount != rhs.missingCount {
                return lhs.missingCount > rhs.missingCount
            }
            if lhs.newestMissingAt != rhs.newestMissingAt {
                return lhs.newestMissingAt > rhs.newestMissingAt
            }
            return lhs.repository.fullName.localizedStandardCompare(rhs.repository.fullName) == .orderedAscending
        }
    }

    private var hasPendingSyncWork: Bool {
        pendingImportedCommitCount > 0 || pendingUpdatedDiffStatCount > 0
    }

    private func resetSyncProgress() {
        pendingImportedCommitCount = 0
        pendingUpdatedDiffStatCount = 0
        importedCommitCount = 0
        updatedDiffStatCount = 0
        lastSyncProgressPublishedAt = .distantPast
        lastSyncSaveAt = .distantPast
        pendingSyncSaveOperationCount = 0
    }

    private func finishSyncProgress() {
        importedCommitCount = pendingImportedCommitCount
        updatedDiffStatCount = pendingUpdatedDiffStatCount
        isSyncing = false
    }

    private func recordSyncProgress(insertedCommits: Int = 0, updatedDiffStats: Int = 0) {
        pendingImportedCommitCount += insertedCommits
        pendingUpdatedDiffStatCount += updatedDiffStats
    }

    private func logSlowSyncOperation(
        _ operation: String,
        startedAt start: Date,
        threshold: TimeInterval
    ) {
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= threshold {
            performanceLogger.warning("\(operation, privacy: .public) took \(Self.formattedMilliseconds(elapsed), privacy: .public)")
        }
    }

    private static func formattedMilliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f ms", interval * 1_000)
    }

    private func publishSyncProgress(_ message: String, force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastSyncProgressPublishedAt) >= syncProgressPublishInterval else {
            return
        }

        importedCommitCount = pendingImportedCommitCount
        updatedDiffStatCount = pendingUpdatedDiffStatCount
        syncMessage = message
        lastSyncProgressPublishedAt = now
        await Task.yield()
    }

    private func saveSyncBatch(modelContext: ModelContext, force: Bool = false) async throws {
        pendingSyncSaveOperationCount += 1
        let now = Date()
        let shouldSave = force ||
            pendingSyncSaveOperationCount >= syncSaveOperationLimit ||
            now.timeIntervalSince(lastSyncSaveAt) >= syncSaveInterval

        if shouldSave {
            let saveStart = Date()
            try modelContext.save()
            logSlowSyncOperation(
                "SwiftData sync save after \(pendingSyncSaveOperationCount.formatted()) pending operations",
                startedAt: saveStart,
                threshold: 0.05
            )
            pendingSyncSaveOperationCount = 0
            lastSyncSaveAt = now
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: syncUIPacingDelay)
    }

    private func flushSyncBatch(modelContext: ModelContext) async throws {
        try await saveSyncBatch(modelContext: modelContext, force: true)
    }

    private func syncRepositoryCommits(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        fallbackSince: Date,
        minimumRescanSince: Date? = nil,
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
            overlap: commitSyncOverlap,
            minimumRescanSince: minimumRescanSince
        )
        var existingCommitIDs: Set<String>?
        let usedHistoryStats = try await syncCommitHistoryPagesIfAvailable(
            repository,
            api: api,
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
            try await saveSyncBatch(modelContext: modelContext)
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
        try await saveSyncBatch(modelContext: modelContext)
        return RepositorySyncResult(updateSince: updateSince, usedHistoryStats: usedHistoryStats)
    }

    private func backfillRepositoryHistory(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        since: Date,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        var usedHistoryStats = try await syncMissingDiffStatsFromHistory(
            repository,
            api: api,
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
                since: since,
                until: until,
                phase: "Backfilling history",
                maxPages: maxPages,
                existingCommitIDs: &existingCommitIDs,
                modelContext: modelContext
            )
        }

        repository.lastSyncedAt = Date()
        try await saveSyncBatch(modelContext: modelContext)
        return usedHistoryStats
    }

    private func syncMissingDiffStatsFromHistory(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
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
        since: Date,
        until: Date?,
        phase: String,
        maxPages: Int?,
        modelContext: ModelContext
    ) async throws -> Bool {
        var pageBudget = maxPages ?? Int.max
        let result = try await syncCommitHistoryPagesWithBudget(
            repository,
            api: api,
            since: since,
            until: until,
            phase: phase,
            pageBudget: &pageBudget,
            modelContext: modelContext
        )
        return result.completed
    }

    private func syncCommitHistoryPagesWithBudget(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
        since: Date,
        until: Date?,
        phase: String,
        pageBudget: inout Int,
        modelContext: ModelContext
    ) async throws -> HistoryPageSyncResult {
        var existingCommits = try existingCommitRecords(
            repositoryFullName: repository.fullName,
            authoredSince: since,
            authoredBefore: until,
            modelContext: modelContext
        )
        var page = 1
        var after: String?
        var pagesUsed = 0
        var updatedStats = 0

        while pageBudget > 0 {
            if pageBudget != Int.max {
                pageBudget -= 1
            }

            try Task.checkCancellation()
            await publishSyncProgress("\(phase) \(repository.fullName) page \(page)")

            let history = try await api.commitHistoryPage(
                owner: repository.ownerLogin,
                repo: repository.name,
                since: since,
                until: until,
                after: after,
                perPage: commitPageSize
            )
            pagesUsed += 1

            let upsertStart = Date()
            let result = try upsertGraphQLCommits(
                history.commits,
                repository: repository,
                existingCommits: &existingCommits,
                modelContext: modelContext
            )
            logSlowSyncOperation(
                "\(phase) GraphQL upsert \(repository.fullName) page \(page) with \(history.commits.count.formatted()) commits",
                startedAt: upsertStart,
                threshold: 0.05
            )
            recordSyncProgress(insertedCommits: result.inserted, updatedDiffStats: result.updatedStats)
            updatedStats += result.updatedStats
            try await saveSyncBatch(modelContext: modelContext)
            await publishSyncProgress("\(phase) \(repository.fullName): \(pendingImportedCommitCount) new commits, \(pendingUpdatedDiffStatCount) line stats")

            guard history.hasNextPage, let endCursor = history.endCursor else {
                return HistoryPageSyncResult(pagesUsed: pagesUsed, completed: true, updatedStats: updatedStats)
            }

            after = endCursor
            page += 1
        }

        return HistoryPageSyncResult(pagesUsed: pagesUsed, completed: false, updatedStats: updatedStats)
    }

    private func syncCommitPages(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
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
            await publishSyncProgress("\(phase) \(repository.fullName) page \(page)")

            let commits = try await api.commitPage(
                owner: repository.ownerLogin,
                repo: repository.name,
                since: since,
                until: until,
                page: page,
                perPage: commitPageSize
            )
            guard !commits.isEmpty else {
                return
            }

            let upsertStart = Date()
            let inserted = try upsertCommits(
                commits,
                repository: repository,
                existingCommitIDs: &existingCommitIDs,
                modelContext: modelContext
            )
            logSlowSyncOperation(
                "\(phase) REST upsert \(repository.fullName) page \(page) with \(commits.count.formatted()) commits",
                startedAt: upsertStart,
                threshold: 0.05
            )
            recordSyncProgress(insertedCommits: inserted)
            try await saveSyncBatch(modelContext: modelContext)
            await publishSyncProgress("\(phase) \(repository.fullName): \(pendingImportedCommitCount) new commits")

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
        authoredBefore: Date? = nil,
        order: DiffStatsBackfillOrder = .newestFirst,
        modelContext: ModelContext
    ) async throws -> (attempted: Int, updated: Int) {
        guard requestLimit > 0 else {
            return (0, 0)
        }

        let candidates = try commitsNeedingDiffStats(
            repositoryFullName: repository.fullName,
            authoredSince: authoredSince,
            authoredBefore: authoredBefore,
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
            await publishSyncProgress("Fetching stats \(repository.fullName): \(attempted) of \(min(candidates.count, requestLimit))")

            do {
                let detail = try await api.commitDetail(
                    owner: repository.ownerLogin,
                    repo: repository.name,
                    sha: commit.sha
                )
                commit.applyDiffStats(from: detail)
                updated += 1
                recordSyncProgress(updatedDiffStats: 1)
            } catch {
                commit.markDiffStatsFailed(error.localizedDescription)
            }

            if attempted % 10 == 0 {
                try await saveSyncBatch(modelContext: modelContext)
            }
        }

        if attempted > 0 {
            try await saveSyncBatch(modelContext: modelContext)
        }
        return (attempted, updated)
    }

    private func commitsNeedingDiffStats(
        repositoryFullName: String,
        authoredSince: Date? = nil,
        authoredBefore: Date? = nil,
        order: DiffStatsBackfillOrder = .newestFirst,
        fetchLimit: Int? = nil,
        modelContext: ModelContext
    ) throws -> [GitCommitRecord] {
        let fullName = repositoryFullName
        let sortOrder: SortOrder = order == .newestFirst ? .reverse : .forward
        let now = Date()
        let retryInterval = diffStatsRetryInterval
        func applyFetchLimit(_ descriptor: inout FetchDescriptor<GitCommitRecord>) {
            if let fetchLimit {
                descriptor.fetchLimit = fetchLimit
            }
        }

        if let authoredSince, let authoredBefore {
            var descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.authoredAt >= authoredSince &&
                        $0.authoredAt < authoredBefore &&
                        $0.changedFileCount == nil
                },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            applyFetchLimit(&descriptor)
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else if let authoredSince {
            var descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.authoredAt >= authoredSince &&
                        $0.changedFileCount == nil
                },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            applyFetchLimit(&descriptor)
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else if let authoredBefore {
            var descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.authoredAt < authoredBefore &&
                        $0.changedFileCount == nil
                },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            applyFetchLimit(&descriptor)
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else {
            var descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.changedFileCount == nil
                },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            applyFetchLimit(&descriptor)
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
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

    private func missingDiffStatsMonthInterval(
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

        let calendar = Calendar.current
        let rawMonthStart = CalendarMath.monthStart(for: newestMissingDate, calendar: calendar)
        let start = max(rawMonthStart, since)
        let end = calendar.date(byAdding: .month, value: 1, to: rawMonthStart) ?? newestMissingDate.addingTimeInterval(1)
        guard start < end else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func syncCompleteMessage(prefix: String = "Sync complete", failedRepositoryCount: Int) -> String {
        var parts = ["\(prefix): \(pendingImportedCommitCount) new commits"]
        if pendingUpdatedDiffStatCount > 0 {
            parts.append("updated \(pendingUpdatedDiffStatCount) diff stats")
        }
        if failedRepositoryCount > 0 {
            parts.append("\(failedRepositoryCount) repositories need another sync")
        }
        return parts.joined(separator: ". ")
    }

    private func historyIndexCompleteMessage(
        completedMonths: Int,
        completedRepositories: Int,
        touchedRepositories: Int,
        pageBudgetExhausted: Bool,
        failedRepositoryCount: Int
    ) -> String {
        var parts = ["Historical index: \(pendingImportedCommitCount.formatted()) commits, \(pendingUpdatedDiffStatCount.formatted()) line stats"]
        if completedMonths > 0 {
            parts.append("\(completedMonths.formatted()) months indexed")
        }
        if completedRepositories > 0 {
            parts.append("\(completedRepositories.formatted()) repositories complete")
        }
        if pageBudgetExhausted {
            parts.append("run again for more")
        } else if touchedRepositories == 0 && failedRepositoryCount == 0 {
            parts.append("already complete")
        }
        if failedRepositoryCount > 0 {
            parts.append("\(failedRepositoryCount.formatted()) repositories need retry")
        }
        return parts.joined(separator: ". ")
    }

    private func todaySyncCompleteMessage(failedRepositoryCount: Int) -> String {
        var parts = ["Today refreshed: \(pendingImportedCommitCount) new commits"]
        if pendingUpdatedDiffStatCount > 0 {
            parts.append("updated \(pendingUpdatedDiffStatCount) diff stats")
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
        authoredBefore: Date? = nil,
        modelContext: ModelContext
    ) throws -> [String: GitCommitRecord] {
        let fullName = repositoryFullName
        let records: [GitCommitRecord]
        if let authoredSince, let authoredBefore {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.authoredAt >= authoredSince &&
                        $0.authoredAt < authoredBefore
                }
            )
            records = try modelContext.fetch(descriptor)
        } else if let authoredSince {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt >= authoredSince }
            )
            records = try modelContext.fetch(descriptor)
        } else if let authoredBefore {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt < authoredBefore }
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

    private func demoRepository(
        modelContext: ModelContext,
        includeFixtureDetails: Bool = false
    ) throws -> GitRepositoryRecord {
        let demoID: Int64 = includeFixtureDetails ? 941_000 : -941
        var descriptor = FetchDescriptor<GitRepositoryRecord>(
            predicate: #Predicate { $0.id == demoID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let repo = GitRepositoryRecord(
            id: demoID,
            ownerLogin: includeFixtureDetails ? DemoFixtureIdentity.repositoryOwner : "captains-log",
            name: includeFixtureDetails ? DemoFixtureIdentity.repositoryName : "demo",
            fullName: includeFixtureDetails ? DemoFixtureIdentity.repositoryFullName : "captains-log/demo",
            accountLogin: includeFixtureDetails ? DemoFixtureIdentity.login : nil,
            isPrivate: false,
            isSelected: true,
            htmlURL: DemoFixtureIdentity.url
        )
        modelContext.insert(repo)
        return repo
    }

    private func seedFixtureRepositoryList(modelContext: ModelContext) throws {
        let calendar = Calendar.current
        for fixture in DemoFixtureIdentity.companionRepositories {
            let fixtureID = fixture.id
            var descriptor = FetchDescriptor<GitRepositoryRecord>(
                predicate: #Predicate { $0.id == fixtureID }
            )
            descriptor.fetchLimit = 1

            let repository: GitRepositoryRecord
            if let existing = try modelContext.fetch(descriptor).first {
                repository = existing
            } else {
                let fullName = "\(DemoFixtureIdentity.repositoryOwner)/\(fixture.name)"
                repository = GitRepositoryRecord(
                    id: fixture.id,
                    ownerLogin: DemoFixtureIdentity.repositoryOwner,
                    name: fixture.name,
                    fullName: fullName,
                    accountLogin: DemoFixtureIdentity.login,
                    isPrivate: fixture.isPrivate,
                    isSelected: fixture.isSelected,
                    htmlURL: URL(string: "https://github.com/\(fullName)") ?? DemoFixtureIdentity.url
                )
                modelContext.insert(repository)
            }

            repository.accountLogin = DemoFixtureIdentity.login
            repository.isSelected = fixture.isSelected
            repository.lastSyncedAt = Date()
            repository.pushedAt = calendar.date(byAdding: .day, value: -fixture.pushedDayOffset, to: Date())
            repository.historyBackfillCompletedAt = Date()
            repository.historyBackfillLowerBound = calendar.date(byAdding: .year, value: -1, to: Date())
            repository.historyBackfillLastError = nil
        }
    }

    private func fetchCommit(id: String, modelContext: ModelContext) throws -> GitCommitRecord? {
        var descriptor = FetchDescriptor<GitCommitRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func seedDemoSummary(
        modelContext: ModelContext,
        repo: GitRepositoryRecord,
        calendar: Calendar
    ) throws {
        let featuredDate = demoFixtureFeaturedDate(calendar: calendar)
        let featuredDayKey = GitCommitRecord.dayKey(for: featuredDate, calendar: calendar)
        let sourceIDs = try modelContext.fetch(FetchDescriptor<GitCommitRecord>())
            .filter { $0.repositoryFullName == repo.fullName && $0.dayKey == featuredDayKey }
            .map(\.id)

        guard !sourceIDs.isEmpty else {
            return
        }

        let draft = JournalSummaryDraft(
            title: "Built the app spine",
            narrative: "The day focused on turning GitHub history into a readable work record. The fixture covers sync state, changed-line stats, Work Map data, and journal evidence so screen QA can run without a live GitHub account.",
            bullets: [
                "Connected the dashboard to demo commits with changed-line stats.",
                "Added enough source evidence to open day and commit detail screens.",
                "Marked history coverage complete for the fixture repository."
            ],
            tags: ["fixture", "sync", "journal"]
        )
        let generatedAt = calendar.date(byAdding: .hour, value: 15, to: featuredDate) ?? featuredDate

        let dayKey = GitCommitRecord.dayKey(for: featuredDate, calendar: calendar)
        var descriptor = FetchDescriptor<DailyJournalSummaryRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            _ = existing.update(from: draft, sourceCommitIDs: sourceIDs, modelName: "UI Fixture")
            existing.generatedAt = generatedAt
        } else {
            modelContext.insert(
                DailyJournalSummaryRecord(
                    date: featuredDate,
                    title: draft.title,
                    narrative: draft.narrative,
                    bullets: draft.bullets,
                    tags: draft.tags,
                    sourceCommitIDs: sourceIDs,
                    generatedAt: generatedAt,
                    modelName: "UI Fixture"
                )
            )
        }
    }

    private func demoFixtureFeaturedDate(calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -2, to: today) ?? today
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
        case lockedSummary
        case syncInProgress

        var errorDescription: String? {
            switch self {
            case .missingModelContext:
                "Local storage is not ready yet."
            case .lockedSummary:
                "Unlock this Captain's Log before regenerating it."
            case .syncInProgress:
                "Wait for the current sync to finish before clearing imported history."
            }
        }
    }
}
