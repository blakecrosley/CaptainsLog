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
    @State private var isShowingDayDetail = false
    @State private var aiCredentialRevision = 0
    @State private var didStartPerformanceHeartbeat = false
    @State private var didPrepareDebugFixture = false
    @State private var lastHistoryBackfillScheduleAttempt: Date?
    @State private var generationError: String?
    @State private var isGeneratingSummary = false
    @State private var identityAliasesText = ""
    #if DEBUG
    @State private var didPresentDebugScreenshotRoute = false
    @State private var debugScreenshotSheetRoute: DebugScreenshotRoute?
    #endif
    @AppStorage(WorkIdentityPreferences.scopeKey) private var workIdentityScopeRaw = WorkIdentityScope.allSelectedRepos.rawValue
    @AppStorage("work.displayMetric") private var workDisplayMetricRaw = WorkDisplayMetric.changes.rawValue

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

    private var workDisplayMetric: WorkDisplayMetric {
        WorkDisplayMetric(rawValue: workDisplayMetricRaw) ?? .changes
    }

    private var workDisplayMetricBinding: Binding<WorkDisplayMetric> {
        Binding {
            workDisplayMetric
        } set: { newValue in
            workDisplayMetricRaw = newValue.rawValue
        }
    }

    private var identityAliases: Set<String> {
        WorkIdentitySelection.aliases(from: identityAliasesText)
    }

    private var preferredAIProvider: AIProvider {
        _ = aiCredentialRevision
        return AIProviderCredentialStore.shared.preferredProvider
    }

    private var hasCloudAIKey: Bool {
        _ = aiCredentialRevision
        return AIProviderCredentialStore.shared.hasAnyCloudKey()
    }

    private var hasPreferredAIKey: Bool {
        _ = aiCredentialRevision
        return AIProviderCredentialStore.shared.hasKey(for: preferredAIProvider)
    }

    private var aiSettingsSubtitle: String {
        if hasPreferredAIKey {
            return "\(preferredAIProvider.displayName) selected, key attached"
        }
        if hasCloudAIKey {
            return "\(preferredAIProvider.displayName) selected; choose an attached provider or add a key"
        }
        return "Attach your own OpenAI or Anthropic API key"
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
            credentialStore: .shared,
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
                #if DEBUG
                .fullScreenCover(item: $debugScreenshotSheetRoute) { route in
                    debugScreenshotSheet(for: route)
                }
                #endif
                .navigationDestination(isPresented: $isShowingDayDetail) {
                    dayDetailPage
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
                #if DEBUG
                if prepareDebugFixtureIfNeeded() {
                    presentDebugScreenshotRouteIfNeeded()
                    return
                }
                #endif
                if CaptainsLogApp.isUITesting {
                    return
                }
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
                displayMetric: workDisplayMetricBinding,
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
                onShowMonth: { isShowingMonthCalendar = true },
                onShowDayDetail: { isShowingDayDetail = true }
            )
        }
    }

    private var dayDetailPage: some View {
        let data = workData

        return ScrollView {
            DayDetailView(
                selectedDate: selectedDate,
                commits: data.selectedCommits,
                workSnapshot: data.selectedWorkSnapshot,
                summary: data.selectedSummary,
                isGeneratingSummary: isGeneratingSummary,
                generationError: generationError,
                generationProvider: preferredJournalProvider
            )
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppSurface.backgroundGradient.ignoresSafeArea())
        .navigationTitle(selectedDate.formatted(.dateTime.month(.abbreviated).day().year()))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let summary = data.selectedSummary {
                    Button {
                        toggleSelectedSummaryLock()
                    } label: {
                        Image(systemName: summary.isLocked ? "lock.fill" : "lock.open")
                    }
                    .accessibilityLabel(summary.isLocked ? "Unlock journal" : "Lock journal")
                }

                Button {
                    generateSummary()
                } label: {
                    Image(systemName: preferredJournalProvider?.symbolName ?? "sparkles")
                }
                .disabled(!canGenerateSummary || isGeneratingSummary)
                .accessibilityLabel(data.selectedSummary == nil ? "Generate journal" : "Regenerate journal")
            }
        }
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
            authPanel
            modelGate
        }
    }

    private var repositorySettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    AccountSettingsCard(
                        activeLogin: activeLogin,
                        isSignedIn: appModel.isSignedIn,
                        repositoryCount: githubRepositories.count,
                        onSignIn: {
                            Task { await appModel.signIn() }
                        },
                        onSignOut: {
                            appModel.signOut()
                        }
                    )

                    repoPanel

                    WorkIdentitySettingsCard(
                        scope: workIdentityScopeBinding,
                        activeLogin: activeLogin,
                        aliasesText: $identityAliasesText,
                        visibleCommitCount: visibleCommits.count,
                        allSelectedCommitCount: allSelectedCommits.count
                    )

                    Kit941.Card {
                        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                            NavigationLink {
                                AISettingsView(credentialRevision: $aiCredentialRevision)
                            } label: {
                                SettingsDisclosureRow(
                                    title: "AI providers",
                                    description: aiSettingsSubtitle,
                                    systemImage: hasPreferredAIKey ? "key.fill" : "key"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(AppSurface.divider.opacity(0.6))

                            NavigationLink {
                                PrivacyDataView(
                                    isSignedIn: appModel.isSignedIn,
                                    activeLogin: activeLogin,
                                    selectedRepositoryCount: githubRepositories.filter(\.isSelected).count,
                                    importedCommitCount: commits.count,
                                    journalCount: summaries.count,
                                    hasCloudAIKey: hasCloudAIKey,
                                    preferredProviderName: preferredAIProvider.displayName,
                                    onClearImportedHistory: clearImportedHistory
                                )
                            } label: {
                                SettingsDisclosureRow(
                                    title: "Privacy & Data",
                                    description: "What stays on device and what leaves when you sync or generate.",
                                    systemImage: "hand.raised"
                                )
                            }
                            .buttonStyle(.plain)
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppSurface.accent)
                    .frame(width: 34, height: 34)
                    .background(AppSurface.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Captain's Log")
                        .kit941Font(.title, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                        .lineLimit(1)
                    Text("GitHub work journal")
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modelGate: some View {
        if hasPreferredAIKey {
            HStack(spacing: Kit941.Spacing.sm) {
                Image(systemName: preferredAIProvider.symbolName)
                    .foregroundStyle(AppSurface.accent)
                Text("\(preferredAIProvider.displayName) summaries ready")
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
                    Text("On-device summaries ready")
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

                    VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                        if githubRepositories.isEmpty, appModel.githubRepositoryApprovalURL != nil {
                            AppActionRow(
                                title: "Approve Repository Access",
                                description: "Open GitHub and choose repositories for Captain's Log.",
                                systemImage: "checklist",
                                isProminent: true,
                                action: openGitHubRepositorySelection
                            )
                        }

                        AppActionRow(
                            title: "GitHub Access",
                            description: "Refresh repository access after changes in GitHub.",
                            systemImage: "arrow.clockwise",
                            action: {
                                Task { await appModel.refreshRepositories() }
                            }
                        )

                        AppActionRow(
                            title: "Sign Out",
                            description: "Remove this GitHub session from the device.",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            isDestructive: true,
                            showsChevron: false,
                            action: {
                                appModel.signOut()
                            }
                        )
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

    #if DEBUG
    @ViewBuilder
    private func debugScreenshotSheet(for route: DebugScreenshotRoute) -> some View {
        NavigationStack {
            switch route {
            case .repositories:
                RepositorySelectionView(
                    repositories: repositoryPanelRepositories,
                    appInstallURL: appModel.githubRepositoryApprovalURL,
                    onRefreshRepos: {},
                    onInstallApp: {}
                )
            case .ai:
                AISettingsView(credentialRevision: $aiCredentialRevision)
            case .privacy:
                PrivacyDataView(
                    isSignedIn: appModel.isSignedIn,
                    activeLogin: activeLogin,
                    selectedRepositoryCount: githubRepositories.filter(\.isSelected).count,
                    importedCommitCount: commits.count,
                    journalCount: summaries.count,
                    hasCloudAIKey: hasCloudAIKey,
                    preferredProviderName: preferredAIProvider.displayName,
                    onClearImportedHistory: clearImportedHistory
                )
            case .dayDetail:
                EmptyView()
            }
        }
    }

    @MainActor
    private func presentDebugScreenshotRouteIfNeeded() {
        guard !didPresentDebugScreenshotRoute,
              let route = DebugScreenshotRoute.current else {
            return
        }

        didPresentDebugScreenshotRoute = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            switch route {
            case .dayDetail:
                isShowingDayDetail = true
            case .repositories, .ai, .privacy:
                debugScreenshotSheetRoute = route
            }
        }
    }
    #endif

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

    #if DEBUG
    private func prepareDebugFixtureIfNeeded() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let shouldSeedFixture = environment["CAPTAINS_LOG_UI_FIXTURE"] == "1"
            || environment["CAPTAINS_LOG_DEBUG_FIXTURE"] == "1"
        guard shouldSeedFixture else {
            return false
        }

        guard !didPrepareDebugFixture else {
            return true
        }

        didPrepareDebugFixture = true
        do {
            try appModel.seedDemoData(includeFixtureDetails: true)
            reloadCommitSnapshot()
            selectLatestCommitDateIfUseful(force: true)
            generationError = nil
        } catch {
            generationError = error.localizedDescription
            rootViewLogger.error("Failed to prepare UI fixture: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }
    #endif

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
            lastHistoryBackfillScheduleAttempt = nil
            BackgroundHistoryIndexer.cancelPending()
            return
        }

        let now = Date()
        if let lastAttempt = lastHistoryBackfillScheduleAttempt,
           now.timeIntervalSince(lastAttempt) < Self.historyBackfillScheduleAttemptInterval {
            return
        }

        lastHistoryBackfillScheduleAttempt = now
        BackgroundHistoryIndexer.schedule()
    }

    private static let historyBackfillScheduleAttemptInterval: TimeInterval = 15 * 60

    private func loadIdentityAliases() {
        identityAliasesText = WorkIdentityPreferences.loadAliasesText(for: activeLogin)
    }

    private func saveIdentityAliases(_ text: String) {
        WorkIdentityPreferences.saveAliasesText(text, for: activeLogin)
    }

    private var canGenerateSummary: Bool {
        let data = workData
        return preferredJournalProvider != nil
            && !data.selectedCommits.isEmpty
            && data.selectedSummary?.isLocked != true
    }

    private var lowerCalendarBound: Date {
        if let oldest = visibleCommits.map(\.authoredAt).min() {
            return oldest
        }
        return Calendar.current.date(byAdding: .day, value: -370, to: Date()) ?? Date()
    }

    private func generateSummary() {
        let data = workData
        guard data.selectedSummary?.isLocked != true else {
            generationError = "Unlock this Captain's Log before regenerating it."
            return
        }

        let targetDate = selectedDate
        let evidence = data.selectedCommits.map(JournalCommitEvidence.init(record:))
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

    private func toggleSelectedSummaryLock() {
        let targetDate = selectedDate
        do {
            try appModel.toggleSummaryLock(date: targetDate)
            generationError = nil
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func clearImportedHistory() throws -> LocalHistoryDeletionResult {
        let result = try appModel.clearImportedHistory()
        commits = []
        rebuildWorkMetrics()
        selectedDate = Date()
        generationError = nil
        return result
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

#if DEBUG
enum DebugScreenshotRoute: String, Identifiable {
    case dayDetail = "day-detail"
    case repositories
    case ai
    case privacy

    var id: String { rawValue }

    static var current: DebugScreenshotRoute? {
        guard let route = ProcessInfo.processInfo.environment["CAPTAINS_LOG_SCREENSHOT_ROUTE"] else {
            return nil
        }
        return DebugScreenshotRoute(rawValue: route)
    }
}
#endif

private struct RootWorkData {
    let metrics: WorkMetrics
    let selectedCommits: [GitCommitRecord]
    let selectedWorkSnapshot: DayWorkSnapshot
    let selectedSummary: DailyJournalSummaryRecord?
}

private struct AccountSettingsCard: View {
    let activeLogin: String?
    let isSignedIn: Bool
    let repositoryCount: Int
    let onSignIn: @MainActor @Sendable () -> Void
    let onSignOut: @MainActor @Sendable () -> Void

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.plus")
                        .foregroundStyle(AppSurface.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GitHub Account")
                            .kit941Font(.title, weight: .semibold)
                        Text(statusText)
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                if isSignedIn {
                    AppActionRow(
                        title: "Sign Out",
                        description: "Remove this GitHub session from the device.",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true,
                        showsChevron: false,
                        action: onSignOut
                    )
                } else {
                    AppActionRow(
                        title: "Sign in with GitHub",
                        description: "Connect an account before syncing repository history.",
                        systemImage: "person.crop.circle.badge.checkmark",
                        isProminent: true,
                        action: onSignIn
                    )
                }
            }
        }
    }

    private var statusText: String {
        guard isSignedIn else {
            return "Not connected"
        }
        let login = activeLogin ?? "Connected"
        if repositoryCount > 0 {
            return "\(login), \(repositoryCount.formatted()) repositories available"
        }
        return "\(login), repository access pending"
    }
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

private struct SettingsDisclosureRow: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Kit941.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppSurface.accent)
                .frame(width: 38, height: 38)
                .background(AppSurface.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .kit941Font(.label, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)
                Text(description)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Kit941.Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppSurface.secondaryText)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityIdentifier("actionRow.\(title)")
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
