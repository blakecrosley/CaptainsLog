import Foundation
import OSLog
import SwiftData
import SwiftUI

enum RepositorySyncWindow {
    static func updateSince(
        fallbackSince: Date,
        lastSyncedAt: Date?,
        newestCommitDate: Date?,
        overlap: TimeInterval
    ) -> Date {
        guard newestCommitDate != nil else {
            return fallbackSince
        }

        return [
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

private struct HistoryBackfillStepResult {
    let pagesUsed: Int
    let completedMonth: Bool
    let completedRepository: Bool
    let hadWork: Bool
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
    private let syncLogger = Logger(subsystem: "com.blakecrosley.captainslog", category: "sync")
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
    private let historicalBackfillPageBudgetPerRun = 40
    private let diffStatsRetryInterval: TimeInterval = 3_600

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
                syncLogger.info("No saved GitHub token found during session load")
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
            syncLogger.info("Loaded GitHub session for \(loadedViewer.login, privacy: .public)")
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Load GitHub session") {
                return
            }
            token = nil
            viewer = nil
            authState = .failed(error.localizedDescription)
            syncLogger.error("Failed to load GitHub session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restoreSessionForSyncIfNeeded() async -> Bool {
        if token != nil, viewer != nil {
            return true
        }

        syncMessage = "Restoring GitHub session"
        syncLogger.info("Sync requested without an in-memory GitHub session; restoring from keychain")

        do {
            guard let savedToken = try KeychainTokenStore.readToken() else {
                syncMessage = "Sign in to GitHub again"
                authState = .signedOut
                syncLogger.error("No saved GitHub token available for sync")
                return false
            }

            token = savedToken
            let loadedViewer = try await GitHubAPIClient(token: savedToken, appSlug: githubAppSlug).viewer()
            viewer = loadedViewer

            if let modelContext {
                try upsertAccount(loadedViewer, isActive: true, modelContext: modelContext)
                try modelContext.save()
            }

            try KeychainTokenStore.saveToken(savedToken, login: loadedViewer.login)
            authState = .signedIn(loadedViewer)
            syncLogger.info("Restored GitHub session for \(loadedViewer.login, privacy: .public)")
            return true
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Restore GitHub session") {
                return false
            }
            token = nil
            viewer = nil
            syncMessage = "GitHub session failed: \(error.localizedDescription)"
            authState = .failed(error.localizedDescription)
            syncLogger.error("Failed to restore GitHub session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func handleUnauthorizedGitHubError(
        _ error: Error,
        operation: String,
        login: String? = nil
    ) -> Bool {
        guard let githubError = error as? GitHubError, githubError.isUnauthorized else {
            return false
        }

        let invalidLogin = login ?? viewer?.login
        if let invalidLogin {
            try? KeychainTokenStore.deleteToken(login: invalidLogin)
        } else {
            try? KeychainTokenStore.deleteToken()
        }

        token = nil
        viewer = nil
        pendingDeviceCode = nil
        repositoryApprovalURL = githubAppInstallURL

        let message = "GitHub session expired. Sign in again."
        syncMessage = message
        authMessage = message
        authState = .signedOut
        syncLogger.error("\(operation, privacy: .public) failed because GitHub rejected the saved token with HTTP 401")
        return true
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
            if handleUnauthorizedGitHubError(error, operation: "Switch GitHub account", login: account.login) {
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
            if handleUnauthorizedGitHubError(error, operation: "Refresh repositories") {
                return
            }
            syncMessage = error.localizedDescription
        }
    }

    func syncSelectedRepositories(
        lookbackDays: Int = 370
    ) async {
        syncLogger.info("Sync updates requested")
        guard !isSyncing else {
            syncMessage = "A sync is already running"
            syncLogger.info("Sync updates ignored because sync is already running")
            return
        }
        guard let modelContext else {
            syncMessage = StorageError.missingModelContext.localizedDescription
            syncLogger.error("Sync updates failed: missing model context")
            return
        }
        guard await restoreSessionForSyncIfNeeded() else {
            syncLogger.error("Sync updates failed: no GitHub session")
            return
        }
        guard let token else {
            syncMessage = "Sign in to GitHub again"
            authState = .signedOut
            syncLogger.error("Sync updates failed: token nil after restore")
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
                        fallbackSince: fallbackSince,
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
                    syncMessage = "Sync canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Sync updates") {
                        return
                    }
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                syncMessage = syncCompleteMessage(failedRepositoryCount: 0)
            } else if importedCommitCount > 0 || updatedDiffStatCount > 0 {
                syncMessage = syncCompleteMessage(failedRepositoryCount: failedRepositories.count)
            } else if let firstFailure = failedRepositories.first {
                syncMessage = "\(firstFailure.name): \(firstFailure.message)"
            } else {
                syncMessage = "Sync failed"
            }
        } catch {
            if handleUnauthorizedGitHubError(error, operation: "Sync updates") {
                return
            }
            syncMessage = error.localizedDescription
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
        importedCommitCount = 0
        updatedDiffStatCount = 0
        syncMessage = "Filling \(scope.syncTitle) line stats"
        defer { isSyncing = false }

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
                    syncMessage = "Line stats fill canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Selected period line stats") {
                        return
                    }
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                if diffStatsBudget == 0 {
                    syncMessage = "Filled \(updatedDiffStatCount.formatted()) line stats; run again for more"
                } else if importedCommitCount == 0 && updatedDiffStatCount == 0 {
                    syncMessage = "Line stats already complete for selected \(scope.syncTitle)"
                } else {
                    syncMessage = syncCompleteMessage(prefix: "Line stats filled", failedRepositoryCount: 0)
                }
            } else if importedCommitCount > 0 || updatedDiffStatCount > 0 {
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
        importedCommitCount = 0
        updatedDiffStatCount = 0
        syncMessage = "Indexing historical analytics"
        defer { isSyncing = false }

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

            for repository in historyBackfillPriority(selected) {
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
                        touchedRepositories += 1
                    }
                    if result.completedMonth {
                        completedMonths += 1
                    }
                    if result.completedRepository {
                        completedRepositories += 1
                    }
                } catch is CancellationError {
                    syncMessage = "Historical index canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Historical analytics index") {
                        return
                    }
                    repository.markHistoryBackfillFailed(error.localizedDescription)
                    try? modelContext.save()
                    failedRepositories.append((repository.fullName, error.localizedDescription))
                }
            }

            if failedRepositories.isEmpty {
                syncMessage = historyIndexCompleteMessage(
                    completedMonths: completedMonths,
                    completedRepositories: completedRepositories,
                    touchedRepositories: touchedRepositories,
                    pageBudgetExhausted: pageBudget == 0,
                    failedRepositoryCount: 0
                )
            } else if importedCommitCount > 0 || updatedDiffStatCount > 0 {
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
                        fallbackSince: startOfToday,
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
                    syncMessage = "Refresh canceled"
                    return
                } catch {
                    if handleUnauthorizedGitHubError(error, operation: "Refresh today") {
                        return
                    }
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
            if handleUnauthorizedGitHubError(error, operation: "Refresh today") {
                return
            }
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
        try modelContext.save()

        var existingCommits = try existingCommitRecords(
            repositoryFullName: repository.fullName,
            authoredSince: interval.start,
            authoredBefore: interval.end,
            modelContext: modelContext
        )
        var after = startingCursor
        var pagesUsed = 0

        while pageBudget > 0 {
            try Task.checkCancellation()
            let monthLabel = interval.start.formatted(.dateTime.month(.abbreviated).year())
            syncMessage = "Indexing \(repository.fullName) \(monthLabel)"

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

            let result = try upsertGraphQLCommits(
                history.commits,
                repository: repository,
                existingCommits: &existingCommits,
                modelContext: modelContext
            )
            importedCommitCount += result.inserted
            updatedDiffStatCount += result.updatedStats
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
                try modelContext.save()
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
            repository.historyBackfillPageCursor = endCursor
            repository.historyBackfillLastAttemptAt = Date()
            repository.historyBackfillLastError = nil
            after = endCursor
            try modelContext.save()
        }

        return HistoryBackfillStepResult(
            pagesUsed: pagesUsed,
            completedMonth: false,
            completedRepository: false,
            hadWork: pagesUsed > 0
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

    private func syncRepositoryCommits(
        _ repository: GitRepositoryRecord,
        api: GitHubAPIClient,
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
        try modelContext.save()
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
        var existingCommits = try existingCommitRecords(
            repositoryFullName: repository.fullName,
            authoredSince: since,
            authoredBefore: until,
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
                since: since,
                until: until,
                after: after,
                perPage: commitPageSize
            )

            let result = try upsertGraphQLCommits(
                history.commits,
                repository: repository,
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
        authoredBefore: Date? = nil,
        order: DiffStatsBackfillOrder = .newestFirst,
        modelContext: ModelContext
    ) throws -> [GitCommitRecord] {
        let fullName = repositoryFullName
        let sortOrder: SortOrder = order == .newestFirst ? .reverse : .forward
        let now = Date()
        let retryInterval = diffStatsRetryInterval
        if let authoredSince, let authoredBefore {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate {
                    $0.repositoryFullName == fullName &&
                        $0.authoredAt >= authoredSince &&
                        $0.authoredAt < authoredBefore
                },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else if let authoredSince {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt >= authoredSince },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else if let authoredBefore {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName && $0.authoredAt < authoredBefore },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
            return try modelContext.fetch(descriptor).filter {
                $0.needsDiffStatsBackfill(at: now, retryInterval: retryInterval)
            }
        } else {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                predicate: #Predicate { $0.repositoryFullName == fullName },
                sortBy: [SortDescriptor(\.authoredAt, order: sortOrder)]
            )
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

    private func historyIndexCompleteMessage(
        completedMonths: Int,
        completedRepositories: Int,
        touchedRepositories: Int,
        pageBudgetExhausted: Bool,
        failedRepositoryCount: Int
    ) -> String {
        var parts = ["Historical index: \(importedCommitCount.formatted()) commits, \(updatedDiffStatCount.formatted()) line stats"]
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
