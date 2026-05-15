import SwiftData
import SwiftUI
import Kit941
import OSLog

private let rootViewLogger = Logger(subsystem: "com.blakecrosley.captainslog", category: "ui")

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \GitHubAccountRecord.login) private var accounts: [GitHubAccountRecord]
    @Query(sort: \GitRepositoryRecord.fullName) private var repositories: [GitRepositoryRecord]
    @Query(sort: \DailyJournalSummaryRecord.date, order: .reverse) private var summaries: [DailyJournalSummaryRecord]

    @StateObject private var appModel = AppModel()
    @State private var commits: [GitCommitRecord] = []
    @State private var workMetrics = WorkMetrics(commits: [])
    @State private var selectedDate = Date()
    @State private var isShowingMonthCalendar = false
    @State private var isShowingAccountSwitcher = false
    @State private var isShowingRepositorySettings = false
    @State private var isShowingAISettings = false
    @State private var isShowingDayDetail = false
    @State private var aiCredentialRevision = 0
    @State private var didStartPerformanceHeartbeat = false
    @State private var generationError: String?
    @State private var isGeneratingSummary = false
    @State private var identityAliasesText = ""
    @AppStorage(WorkIdentityPreferences.scopeKey) private var workIdentityScopeRaw = WorkIdentityScope.allSelectedRepos.rawValue

    private var githubRepositories: [GitRepositoryRecord] {
        repositories.filter { repository in
            guard repository.isGitHubBacked else {
                return false
            }
            guard let activeLogin else {
                return true
            }
            return repository.accountLogin == nil || repository.accountLogin == activeLogin
        }
    }

    private var repositoryPanelRepositories: [GitRepositoryRecord] {
        appModel.isSignedIn ? githubRepositories : repositories
    }

    private var workData: RootWorkData {
        let metrics = workMetrics
        let selectedCommits = metrics.commits(on: selectedDate)
        let selectedWorkSnapshot = metrics.snapshot(on: selectedDate)
        let key = GitCommitRecord.dayKey(for: selectedDate)
        let selectedCommitIDs = Set(selectedCommits.map(\.id))
        let selectedSummary: DailyJournalSummaryRecord?
        if selectedCommitIDs.isEmpty {
            selectedSummary = nil
        } else {
            selectedSummary = summaries.first { summary in
                guard summary.dayKey == key else {
                    return false
                }
                return !Set(summary.sourceCommitIDs).isDisjoint(with: selectedCommitIDs)
            }
        }

        return RootWorkData(
            metrics: metrics,
            selectedCommits: selectedCommits,
            selectedWorkSnapshot: selectedWorkSnapshot,
            selectedSummary: selectedSummary
        )
    }

    private var viewerLogin: String? {
        if case .signedIn(let viewer) = appModel.authState {
            return viewer.login
        }
        return nil
    }

    private var viewerAvatarURL: URL? {
        if case .signedIn(let viewer) = appModel.authState {
            return viewer.avatarURL
        }
        return nil
    }

    private var activeAccount: GitHubAccountRecord? {
        if let viewerLogin {
            return accounts.first { $0.login == viewerLogin }
        }
        return accounts.first { $0.isActive } ?? accounts.first
    }

    private var activeLogin: String? {
        viewerLogin ?? activeAccount?.login
    }

    private var activeAvatarURL: URL? {
        viewerAvatarURL ?? activeAccount?.avatarURL
    }

    private var visibleCommits: [GitCommitRecord] {
        WorkDataFilter.visibleCommits(
            commits,
            repositories: repositories,
            activeLogin: activeLogin,
            identityScope: workIdentityScope,
            identityAliases: identityAliases
        )
    }

    private var allSelectedCommits: [GitCommitRecord] {
        WorkDataFilter.visibleCommits(
            commits,
            repositories: repositories,
            activeLogin: activeLogin,
            identityScope: .allSelectedRepos
        )
    }

    private var workIdentityScope: WorkIdentityScope {
        WorkIdentityScope(rawValue: workIdentityScopeRaw) ?? .allSelectedRepos
    }

    private var workIdentityScopeBinding: Binding<WorkIdentityScope> {
        Binding {
            workIdentityScope
        } set: { newValue in
            workIdentityScopeRaw = newValue.rawValue
        }
    }

    private var identityAliases: Set<String> {
        WorkIdentitySelection.aliases(from: identityAliasesText)
    }

    private var hasOpenAIKey: Bool {
        _ = aiCredentialRevision
        return AIProviderCredentialStore.shared.hasKey(for: .openai)
    }

    private var selectedRepositoryFingerprint: String {
        githubRepositories
            .map { "\($0.id):\($0.isSelected)" }
            .joined(separator: "|")
    }

    private var repositoryOverviewSnapshot: GitRepositoryOverviewSnapshot {
        GitRepositoryOverviewSnapshot(repositories: githubRepositories)
    }

    private var preferredJournalProvider: JournalSummaryProvider? {
        JournalSummaryProvider.preferred(
            hasOpenAIKey: hasOpenAIKey,
            foundationAvailability: appModel.foundationAvailability
        )
    }

    private var shouldShowOverview: Bool {
        !commits.isEmpty || (appModel.isSignedIn && !githubRepositories.isEmpty)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    AppSurface.backgroundGradient
                        .ignoresSafeArea()

                    mainLayout(maxContentWidth: proxy.size.width >= 900 ? 900 : 760)
                }
                .sheet(isPresented: $isShowingMonthCalendar) {
                    MonthCalendarSheet(
                        selectedDate: $selectedDate,
                        workMetrics: workData.metrics,
                        lowerBound: lowerCalendarBound,
                        upperBound: Date(),
                        initialVisibleDate: Date()
                    )
                    .presentationDetents([.large])
                }
                .sheet(isPresented: $isShowingAccountSwitcher) {
                    accountSwitcherSheet
                }
                .sheet(isPresented: $isShowingRepositorySettings) {
                    repositorySettingsSheet
                }
                .sheet(isPresented: $isShowingAISettings) {
                    AISettingsView(credentialRevision: $aiCredentialRevision)
                }
                .sheet(isPresented: $isShowingDayDetail) {
                    dayDetailSheet
                }
            }
            .navigationTitle("Captain's Log")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .foregroundStyle(AppSurface.primaryText)
            .onAppear {
                appModel.configure(modelContext: modelContext)
                loadIdentityAliases()
                startPerformanceHeartbeatIfNeeded()
                reloadCommitSnapshot()
                selectLatestCommitDateIfUseful()
            }
            .task {
                appModel.configure(modelContext: modelContext)
                loadIdentityAliases()
                startPerformanceHeartbeatIfNeeded()
                reloadCommitSnapshot()
                await appModel.loadSession()
                startForegroundLatestSync()
                selectLatestCommitDateIfUseful()
                scheduleHistoricalBackfillIfNeeded()
            }
            .onChange(of: activeLogin) { _, _ in
                loadIdentityAliases()
                rebuildWorkMetrics()
            }
            .onChange(of: identityAliasesText) { _, newValue in
                saveIdentityAliases(newValue)
                rebuildWorkMetrics()
            }
            .onChange(of: appModel.authState) { _, state in
                guard case .signedIn = state else {
                    scheduleHistoricalBackfillIfNeeded()
                    return
                }
                startForegroundLatestSync()
            }
            .onChange(of: selectedRepositoryFingerprint) { _, _ in
                rebuildWorkMetrics()
                startForegroundLatestSync()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    startForegroundLatestSync()
                case .background:
                    scheduleHistoricalBackfillIfNeeded()
                default:
                    break
                }
            }
        }
    }

    private func mainLayout(maxContentWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                if shouldShowOverview {
                    signedInOverview
                } else {
                    setupStack
                }
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            startForcedLatestSync()
        }
    }

    private var signedInOverview: some View {
        let data = workData
        let repositorySnapshot = repositoryOverviewSnapshot

        return VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            WorkOverviewView(
                selectedDate: $selectedDate,
                workMetrics: data.metrics,
                selectedWorkSnapshot: data.selectedWorkSnapshot,
                selectedSummary: data.selectedSummary,
                repositorySnapshot: repositorySnapshot,
                githubLogin: activeLogin,
                githubAvatarURL: activeAvatarURL,
                isGitHubSignedIn: appModel.isSignedIn,
                isSyncing: appModel.isSyncing,
                syncMessage: appModel.syncMessage,
                importedCommitCount: appModel.importedCommitCount,
                updatedDiffStatCount: appModel.updatedDiffStatCount,
                hasOpenAIKey: hasOpenAIKey,
                workIdentityScope: workIdentityScope,
                identityAliasCount: identityAliases.count,
                onShowAccounts: { isShowingAccountSwitcher = true },
                onSyncLatest: {
                    rootViewLogger.info("Header sync latest tapped")
                    startForcedLatestSync()
                },
                onFillLineStats: { scope, interval in
                    rootViewLogger.info("Period line stats tapped: \(scope.rawValue)")
                    Task(priority: .utility) {
                        await appModel.backfillSelectedPeriodLineStats(scope: scope, interval: interval)
                        reloadCommitSnapshot()
                        scheduleHistoricalBackfillIfNeeded()
                    }
                },
                onShowSettings: { isShowingRepositorySettings = true },
                onShowAISettings: { isShowingAISettings = true },
                onShowMonth: { isShowingMonthCalendar = true },
                onShowDayDetail: { isShowingDayDetail = true }
            )
        }
    }

    private var dayDetailSheet: some View {
        let data = workData

        return NavigationStack {
            ScrollView {
                DayDetailView(
                    selectedDate: selectedDate,
                    commits: data.selectedCommits,
                    workSnapshot: data.selectedWorkSnapshot,
                    summary: data.selectedSummary,
                    isGeneratingSummary: isGeneratingSummary,
                    generationError: generationError,
                    canGenerate: canGenerateSummary,
                    generationProvider: preferredJournalProvider,
                    onGenerate: generateSummary
                )
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Day Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingDayDetail = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var accountSwitcherSheet: some View {
        AccountSwitcherSheet(
            accounts: accounts,
            authState: appModel.authState,
            clientID: appModel.githubClientID,
            authMessage: appModel.authMessage,
            activeLogin: activeLogin,
            onSwitch: { account in
                Task { await appModel.switchAccount(account) }
            },
            onAddAccount: {
                Task { await appModel.signIn() }
            },
            onCompleteSignIn: {
                Task { await appModel.completePendingSignIn() }
            },
            onSignOut: {
                appModel.signOut()
            }
        )
    }

    private var setupStack: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            header
            modelGate
            authPanel
        }
    }

    private var repositorySettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    WorkIdentitySettingsCard(
                        scope: workIdentityScopeBinding,
                        activeLogin: activeLogin,
                        aliasesText: $identityAliasesText,
                        visibleCommitCount: visibleCommits.count,
                        allSelectedCommitCount: allSelectedCommits.count
                    )

                    repoPanel

                    Kit941.Card {
                        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                            HStack(spacing: Kit941.Spacing.sm) {
                                Image(systemName: hasOpenAIKey ? "sparkles" : "sparkles.slash")
                                    .foregroundStyle(AppSurface.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("AI")
                                        .kit941Font(.title, weight: .semibold)
                                    Text(hasOpenAIKey ? "OpenAI key stored on this device" : "OpenAI BYOK not set")
                                        .kit941Font(.caption)
                                        .foregroundStyle(AppSurface.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }

                            Kit941.Button(role: .secondary) {
                                await MainActor.run {
                                    isShowingAISettings = true
                                }
                            } label: {
                                Label("Open AI Settings", systemImage: "key")
                            }
                        }
                    }
                }
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingRepositorySettings = false
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack(spacing: Kit941.Spacing.sm) {
                Image(systemName: "book.pages")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppSurface.accent)
                    .accessibilityHidden(true)

                Text("Captain's Log")
                    .kit941Font(.display, weight: .bold)
                    .foregroundStyle(AppSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text("GitHub history, written as a daily work journal.")
                .kit941Font(.body)
                .foregroundStyle(AppSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modelGate: some View {
        if hasOpenAIKey {
            HStack(spacing: Kit941.Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppSurface.accent)
                Text("OpenAI key attached")
                    .kit941Font(.label)
                    .foregroundStyle(AppSurface.primaryText)
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.sm)
            .background(AppSurface.accent.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
        } else {
            switch appModel.foundationAvailability {
            case .available:
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(AppSurface.accent)
                    Text("Apple Foundation Models available")
                        .kit941Font(.label)
                        .foregroundStyle(AppSurface.primaryText)
                }
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.sm)
                .background(AppSurface.accent.opacity(0.10), in: Capsule())
                .accessibilityElement(children: .combine)
            case .unavailable(let reason):
                Kit941.StatusView(
                    style: .failure,
                    symbol: "apple.intelligence.badge.xmark",
                    headline: "No journal model available",
                    description: LocalizedStringKey(reason)
                )
            }
        }
    }

    @ViewBuilder
    private var authPanel: some View {
        switch appModel.authState {
        case .signedOut, .failed:
            GitHubAuthCard(
                authState: appModel.authState,
                clientID: appModel.githubClientID,
                authMessage: appModel.authMessage,
                onConnect: {
                    Task { await appModel.signIn() }
                },
                onCompleteSignIn: {
                    Task { await appModel.completePendingSignIn() }
                },
                onSeedDemo: {
                    do {
                        try appModel.seedDemoData()
                    } catch {
                        generationError = error.localizedDescription
                    }
                }
            )
        case .requestingCode, .waitingForUser, .completingSignIn:
            GitHubAuthCard(
                authState: appModel.authState,
                clientID: appModel.githubClientID,
                authMessage: appModel.authMessage,
                onConnect: {},
                onCompleteSignIn: {
                    Task { await appModel.completePendingSignIn() }
                },
                onSeedDemo: {}
            )
        case .signedIn(let viewer):
            Kit941.Card {
                VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                    HStack(spacing: Kit941.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppSurface.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewer.login)
                                .kit941Font(.title, weight: .semibold)
                            Text("GitHub connected")
                                .kit941Font(.caption)
                                .foregroundStyle(AppSurface.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }

                    if githubRepositories.isEmpty {
                        Text("Approve access to all repositories or selected repositories in GitHub, then return here to refresh.")
                            .kit941Font(.body)
                            .foregroundStyle(AppSurface.secondaryText)

                        if !appModel.syncMessage.isEmpty {
                            Text(appModel.syncMessage)
                                .kit941Font(.caption)
                                .foregroundStyle(appModel.syncMessage.contains("Contents") ? AppSurface.warning : AppSurface.secondaryText)
                                .lineLimit(3)
                        }
                    } else {
                        Text("\(githubRepositories.count) repositories available")
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }

                    HStack(spacing: Kit941.Spacing.sm) {
                        if githubRepositories.isEmpty, appModel.githubRepositoryApprovalURL != nil {
                            Kit941.Button {
                                await MainActor.run { openGitHubRepositorySelection() }
                            } label: {
                                Label("Approve Repository Access", systemImage: "checklist")
                            }
                        }

                        Kit941.Button(role: .secondary) {
                            await appModel.refreshRepositories()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Kit941.Button(role: .plain) {
                            await appModel.signOut()
                        } label: {
                            Text("Sign out")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func openGitHubRepositorySelection() {
        if let url = appModel.githubRepositoryApprovalURL {
            openURL(url)
        }
    }

    private var repoPanel: some View {
        RepositoryPanel(
            repositories: repositoryPanelRepositories,
            isSyncing: appModel.isSyncing,
            syncMessage: appModel.syncMessage,
            importedCommitCount: appModel.importedCommitCount,
            appInstallURL: appModel.githubRepositoryApprovalURL,
            onRefreshRepos: {
                rootViewLogger.info("Repository panel refresh tapped")
                Task(priority: .utility) {
                    await appModel.refreshRepositories()
                    scheduleHistoricalBackfillIfNeeded()
                }
            },
            onSyncSelected: {
                rootViewLogger.info("Repository panel sync updates tapped")
                startForcedLatestSync()
            },
            onFullSync: {
                rootViewLogger.info("Repository panel index history tapped")
                Task(priority: .utility) {
                    await appModel.fullSyncSelectedRepositories()
                    reloadCommitSnapshot()
                    scheduleHistoricalBackfillIfNeeded()
                }
            },
            onInstallApp: {
                openGitHubRepositorySelection()
            }
        )
    }

    private func startForegroundLatestSync() {
        Task(priority: .utility) {
            await syncLatestForForegroundIfNeeded()
        }
    }

    private func startForcedLatestSync() {
        Task(priority: .utility) {
            await refreshCurrentAccount()
        }
    }

    private func refreshCurrentAccount() async {
        guard appModel.isSignedIn else {
            return
        }
        if githubRepositories.isEmpty {
            await appModel.refreshRepositories()
        }
        let didChange = await appModel.syncLatestIfStale(minimumInterval: 0)
        if didChange {
            reloadCommitSnapshot()
        }
        scheduleHistoricalBackfillIfNeeded()
    }

    private func syncLatestForForegroundIfNeeded() async {
        guard appModel.isSignedIn else {
            return
        }
        if githubRepositories.isEmpty {
            await appModel.refreshRepositories()
        }
        let didChange = await appModel.syncLatestIfStale()
        if didChange {
            reloadCommitSnapshot()
        }
        scheduleHistoricalBackfillIfNeeded()
    }

    private func reloadCommitSnapshot() {
        let start = Date()
        do {
            let descriptor = FetchDescriptor<GitCommitRecord>(
                sortBy: [SortDescriptor(\.authoredAt, order: .reverse)]
            )
            commits = try modelContext.fetch(descriptor)
            rebuildWorkMetrics()
            selectLatestCommitDateIfUseful()
            logSlowUIOperation(
                "reloadCommitSnapshot fetched \(commits.count.formatted()) commits",
                startedAt: start,
                threshold: 0.08
            )
        } catch {
            rootViewLogger.error("Failed to reload commit snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuildWorkMetrics() {
        let start = Date()
        let filteredCommits = visibleCommits
        workMetrics = WorkMetrics(commits: filteredCommits)
        logSlowUIOperation(
            "rebuildWorkMetrics used \(filteredCommits.count.formatted()) visible commits",
            startedAt: start,
            threshold: 0.05
        )
    }

    private func startPerformanceHeartbeatIfNeeded() {
        guard !didStartPerformanceHeartbeat else {
            return
        }
        didStartPerformanceHeartbeat = true

        Task { @MainActor in
            var lastTick = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let now = Date()
                let delay = now.timeIntervalSince(lastTick)
                if delay > 0.55 {
                    rootViewLogger.warning("UI main actor heartbeat delayed \(Self.formattedMilliseconds(delay), privacy: .public)")
                }
                lastTick = now
            }
        }
    }

    private func logSlowUIOperation(
        _ operation: String,
        startedAt start: Date,
        threshold: TimeInterval
    ) {
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= threshold {
            rootViewLogger.warning("\(operation, privacy: .public) took \(Self.formattedMilliseconds(elapsed), privacy: .public)")
        }
    }

    private static func formattedMilliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f ms", interval * 1_000)
    }

    private func scheduleHistoricalBackfillIfNeeded() {
        guard appModel.isSignedIn else {
            BackgroundHistoryIndexer.cancelPending()
            return
        }

        do {
            if try appModel.hasHistoricalAnalyticsBackfillWork(lookbackDays: BackgroundHistoryIndexer.lookbackDays) {
                BackgroundHistoryIndexer.schedule()
            } else {
                BackgroundHistoryIndexer.cancelPending()
            }
        } catch {
            rootViewLogger.error("Failed to inspect history backfill backlog: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadIdentityAliases() {
        identityAliasesText = WorkIdentityPreferences.loadAliasesText(for: activeLogin)
    }

    private func saveIdentityAliases(_ text: String) {
        WorkIdentityPreferences.saveAliasesText(text, for: activeLogin)
    }

    private var canGenerateSummary: Bool {
        preferredJournalProvider != nil && !workData.selectedCommits.isEmpty
    }

    private var lowerCalendarBound: Date {
        if let oldest = visibleCommits.map(\.authoredAt).min() {
            return oldest
        }
        return Calendar.current.date(byAdding: .day, value: -370, to: Date()) ?? Date()
    }

    private func generateSummary() {
        let targetDate = selectedDate
        let evidence = workData.selectedCommits.map(JournalCommitEvidence.init(record:))
        let sourceIDs = evidence.map(\.id)
        generationError = nil
        isGeneratingSummary = true

        Task {
            do {
                let result = try await JournalSummarizer.generate(for: targetDate, evidence: evidence)
                try appModel.saveSummary(
                    date: targetDate,
                    draft: result.draft,
                    sourceCommitIDs: sourceIDs,
                    modelName: result.modelName
                )
                await MainActor.run {
                    isGeneratingSummary = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGeneratingSummary = false
                }
            }
        }
    }

    private func selectLatestCommitDateIfUseful(force: Bool = false) {
        guard let latestCommitDate = visibleCommits.first?.authoredAt else {
            return
        }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latestCommitDate)
        let currentDay = calendar.startOfDay(for: selectedDate)
        let currentSelectionIsEmpty = workData.metrics.commitCount(on: currentDay) == 0
        let currentSelectionIsToday = calendar.isDateInToday(currentDay)

        if force || (currentSelectionIsToday && currentSelectionIsEmpty) {
            selectedDate = latestDay
        }
    }
}

private struct RootWorkData {
    let metrics: WorkMetrics
    let selectedCommits: [GitCommitRecord]
    let selectedWorkSnapshot: DayWorkSnapshot
    let selectedSummary: DailyJournalSummaryRecord?
}

private struct WorkIdentitySettingsCard: View {
    @Binding var scope: WorkIdentityScope
    let activeLogin: String?
    @Binding var aliasesText: String
    let visibleCommitCount: Int
    let allSelectedCommitCount: Int

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(AppSurface.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Work Identity")
                            .kit941Font(.title, weight: .semibold)
                        Text(scope.label)
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                Picker("Work scope", selection: $scope) {
                    ForEach(WorkIdentityScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: Kit941.Spacing.xs) {
                    HStack {
                        Text("Active login")
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                        Spacer(minLength: Kit941.Spacing.sm)
                        Text(activeLogin ?? "None")
                            .kit941Font(.caption, weight: .semibold)
                            .lineLimit(1)
                    }

                    HStack {
                        Text("Counted commits")
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                        Spacer(minLength: Kit941.Spacing.sm)
                        Text(countedCommitsLabel)
                            .kit941Font(.caption, weight: .semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                if scope == .mineAndAliases {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Extra author logins")
                            .kit941Font(.caption, weight: .semibold)
                            .foregroundStyle(AppSurface.secondaryText)
                        TextField("blakeatintrol", text: $aliasesText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var countedCommitsLabel: String {
        switch scope {
        case .allSelectedRepos:
            return allSelectedCommitCount.formatted()
        case .mineAndAliases:
            return "\(visibleCommitCount.formatted()) of \(allSelectedCommitCount.formatted())"
        }
    }
}

enum AppSurface {
    enum Theme: String, Sendable {
        case github

        var prefersDark: Bool { true }
        var fontFamily: Kit941.FontFamily { .system }
        var metricFontDesign: Font.Design { .rounded }

        var background: Color {
            Color(red: 0.051, green: 0.067, blue: 0.090)
        }

        var panelBase: Color {
            Color(red: 0.086, green: 0.106, blue: 0.137)
        }

        var accent: Color {
            Color(red: 0.247, green: 0.725, blue: 0.314)
        }

        var secondaryAccent: Color {
            Color(red: 0.345, green: 0.651, blue: 0.984)
        }

        var tertiaryAccent: Color {
            Color(red: 0.824, green: 0.600, blue: 0.133)
        }

        var warning: Color {
            tertiaryAccent
        }

        var danger: Color {
            Color(red: 0.973, green: 0.318, blue: 0.286)
        }

        var primaryText: Color {
            Color(red: 0.941, green: 0.965, blue: 0.988)
        }

        var secondaryText: Color {
            Color(red: 0.545, green: 0.576, blue: 0.620)
        }

        var tertiaryText: Color {
            Color(red: 0.431, green: 0.463, blue: 0.506)
        }

        var divider: Color {
            Color(red: 0.188, green: 0.224, blue: 0.271)
        }

        var track: Color {
            Color(red: 0.129, green: 0.149, blue: 0.176)
        }

        var selectedStroke: Color {
            accent.opacity(0.72)
        }

        var backgroundStops: [Color] {
            [background, background]
        }

        func panelFill(highlighted: Bool) -> LinearGradient {
            let fill = highlighted ? Color(red: 0.102, green: 0.125, blue: 0.161) : panelBase
            return LinearGradient(colors: [fill, fill], startPoint: .top, endPoint: .bottom)
        }

        func panelStroke(highlighted: Bool) -> Color {
            divider.opacity(highlighted ? 1 : 0.78)
        }

        func panelShadow(highlighted: Bool) -> Color {
            .clear
        }

        func mutedFill(opacity: Double) -> Color {
            track.opacity(opacity)
        }

        func densityColor(level: Int) -> Color {
            switch level {
            case 0: return Color(red: 0.086, green: 0.106, blue: 0.137)
            case 1: return Color(red: 0.055, green: 0.267, blue: 0.161)
            case 2: return Color(red: 0.000, green: 0.427, blue: 0.196)
            case 3: return Color(red: 0.149, green: 0.651, blue: 0.255)
            default: return Color(red: 0.224, green: 0.827, blue: 0.325)
            }
        }

        func languageColor(_ language: String) -> Color {
            switch language {
            case "Swift": return accent
            case "TypeScript": return secondaryAccent
            case "JavaScript": return tertiaryAccent
            case "Python": return Color(red: 0.345, green: 0.651, blue: 0.984)
            case "CSS": return Color(red: 0.635, green: 0.451, blue: 0.961)
            case "HTML": return warning
            case "Docs": return tertiaryAccent
            case "Assets": return secondaryAccent
            case "JSON", "YAML", "Property List": return tertiaryText
            default: return tertiaryText
            }
        }

        func categoryColor(_ category: WorkCategory) -> Color {
            switch category {
            case .code: return accent
            case .tests: return secondaryAccent
            case .docs: return tertiaryAccent
            case .design: return Color(red: 0.859, green: 0.314, blue: 0.584)
            case .infra: return tertiaryText
            case .release: return Color(red: 0.635, green: 0.451, blue: 0.961)
            case .unknown: return tertiaryText
            }
        }
    }

    static let defaultTheme: Theme = .github

    static var currentTheme: Theme {
        defaultTheme
    }

    static var background: Color {
        currentTheme.background
    }

    static var panelBase: Color {
        currentTheme.panelBase
    }

    static var accent: Color {
        currentTheme.accent
    }

    static var secondaryAccent: Color {
        currentTheme.secondaryAccent
    }

    static var tertiaryAccent: Color {
        currentTheme.tertiaryAccent
    }

    static var warning: Color {
        currentTheme.warning
    }

    static var danger: Color {
        currentTheme.danger
    }

    static var primaryText: Color {
        currentTheme.primaryText
    }

    static var secondaryText: Color {
        currentTheme.secondaryText
    }

    static var tertiaryText: Color {
        currentTheme.tertiaryText
    }

    static var divider: Color {
        currentTheme.divider
    }

    static var track: Color {
        currentTheme.track
    }

    static var selectedStroke: Color {
        currentTheme.selectedStroke
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: currentTheme.backgroundStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func metricFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: currentTheme.metricFontDesign)
    }

    static func panelFill(highlighted: Bool = false) -> LinearGradient {
        currentTheme.panelFill(highlighted: highlighted)
    }

    static func panelStroke(highlighted: Bool = false) -> Color {
        currentTheme.panelStroke(highlighted: highlighted)
    }

    static func panelShadow(highlighted: Bool = false) -> Color {
        currentTheme.panelShadow(highlighted: highlighted)
    }

    static func mutedFill(opacity: Double = 1) -> Color {
        currentTheme.mutedFill(opacity: opacity)
    }

    static func densityColor(count: Int) -> Color {
        switch count {
        case 0:
            return densityColor(level: 0)
        case 1:
            return densityColor(level: 1)
        case 2:
            return densityColor(level: 2)
        case 3...5:
            return densityColor(level: 3)
        default:
            return densityColor(level: 4)
        }
    }

    static func densityColor(level: Int) -> Color {
        currentTheme.densityColor(level: level)
    }

    static func languageColor(_ language: String) -> Color {
        currentTheme.languageColor(language)
    }

    static func categoryColor(_ category: WorkCategory) -> Color {
        currentTheme.categoryColor(category)
    }
}

extension View {
    func appPanel(cornerRadius: CGFloat = Kit941.Radius.lg, highlighted: Bool = false) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppSurface.panelFill(highlighted: highlighted))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppSurface.panelStroke(highlighted: highlighted), lineWidth: 1)
            }
            .shadow(color: AppSurface.panelShadow(highlighted: highlighted), radius: highlighted ? 22 : 14, x: 0, y: highlighted ? 10 : 7)
    }
}
