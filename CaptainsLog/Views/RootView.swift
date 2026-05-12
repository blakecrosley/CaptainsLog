import SwiftData
import SwiftUI
import Kit941

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \GitHubAccountRecord.login) private var accounts: [GitHubAccountRecord]
    @Query(sort: \GitRepositoryRecord.fullName) private var repositories: [GitRepositoryRecord]
    @Query(sort: \GitCommitRecord.authoredAt, order: .reverse) private var commits: [GitCommitRecord]
    @Query(sort: \DailyJournalSummaryRecord.date, order: .reverse) private var summaries: [DailyJournalSummaryRecord]

    @StateObject private var appModel = AppModel()
    @State private var selectedDate = Date()
    @State private var isShowingMonthCalendar = false
    @State private var isShowingAccountSwitcher = false
    @State private var isShowingRepositorySettings = false
    @State private var isShowingAISettings = false
    @State private var isShowingDayDetail = false
    @State private var aiCredentialRevision = 0
    @State private var generationError: String?
    @State private var isGeneratingSummary = false

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
        let metrics = WorkMetrics(commits: visibleCommits)
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
            activeLogin: activeLogin
        )
    }

    private var hasOpenAIKey: Bool {
        _ = aiCredentialRevision
        return AIProviderCredentialStore.shared.hasKey(for: .openai)
    }

    private var lastRepositorySyncDate: Date? {
        githubRepositories
            .filter(\.isSelected)
            .compactMap(\.lastSyncedAt)
            .max()
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
                    AppSurface.background
                        .ignoresSafeArea()

                    mainLayout(maxContentWidth: proxy.size.width >= 900 ? 900 : 760)
                }
                .sheet(isPresented: $isShowingMonthCalendar) {
                    MonthCalendarSheet(
                        selectedDate: $selectedDate,
                        workMetrics: workData.metrics,
                        lowerBound: lowerCalendarBound,
                        upperBound: Date()
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
            .onAppear {
                appModel.configure(modelContext: modelContext)
                selectLatestCommitDateIfUseful()
            }
            .task {
                appModel.configure(modelContext: modelContext)
                await appModel.loadSession()
                if githubRepositories.isEmpty, appModel.isSignedIn {
                    await appModel.refreshRepositories()
                }
                selectLatestCommitDateIfUseful()
            }
            .onChange(of: commits.count) { oldCount, newCount in
                if newCount > oldCount {
                    selectLatestCommitDateIfUseful()
                } else {
                    selectedDate = Calendar.current.startOfDay(for: selectedDate)
                }
            }
            .onChange(of: appModel.authState) { _, state in
                guard case .signedIn = state, githubRepositories.isEmpty else {
                    return
                }
                Task {
                    await appModel.refreshRepositories()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, appModel.isSignedIn, githubRepositories.isEmpty else {
                    return
                }
                Task {
                    await appModel.refreshRepositories()
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
            await refreshCurrentAccount()
        }
    }

    private var signedInOverview: some View {
        let data = workData

        return VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            WorkOverviewView(
                selectedDate: $selectedDate,
                workMetrics: data.metrics,
                selectedWorkSnapshot: data.selectedWorkSnapshot,
                selectedSummary: data.selectedSummary,
                repositories: githubRepositories,
                githubLogin: activeLogin,
                githubAvatarURL: activeAvatarURL,
                isSyncing: appModel.isSyncing,
                syncMessage: appModel.syncMessage,
                importedCommitCount: appModel.importedCommitCount,
                updatedDiffStatCount: appModel.updatedDiffStatCount,
                lastSyncedAt: lastRepositorySyncDate,
                hasOpenAIKey: hasOpenAIKey,
                onShowAccounts: { isShowingAccountSwitcher = true },
                onRefreshToday: {
                    Task { await appModel.syncToday() }
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
            .background(AppSurface.background.ignoresSafeArea())
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
                                        .foregroundStyle(.secondary)
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
            .background(AppSurface.background.ignoresSafeArea())
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text("GitHub history, written as a daily work journal.")
                .kit941Font(.body)
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
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
                        .foregroundStyle(.primary)
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
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    if githubRepositories.isEmpty {
                        Text("Approve access to all repositories or selected repositories in GitHub, then return here to refresh.")
                            .kit941Font(.body)
                            .foregroundStyle(.secondary)

                        if !appModel.syncMessage.isEmpty {
                            Text(appModel.syncMessage)
                                .kit941Font(.caption)
                                .foregroundStyle(appModel.syncMessage.contains("Contents") ? Kit941.Status.warning : .secondary)
                                .lineLimit(3)
                        }
                    } else {
                        Text("\(githubRepositories.count) repositories available")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
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
                Task { await appModel.refreshRepositories() }
            },
            onSyncSelected: {
                Task { await appModel.syncSelectedRepositories() }
            },
            onFullSync: {
                Task { await appModel.fullSyncSelectedRepositories() }
            },
            onInstallApp: {
                openGitHubRepositorySelection()
            }
        )
    }

    private func refreshCurrentAccount() async {
        guard appModel.isSignedIn else {
            return
        }
        if githubRepositories.isEmpty {
            await appModel.refreshRepositories()
        } else {
            await appModel.syncToday()
        }
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

enum AppSurface {
    static var background: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Kit941.Surface.background
        #endif
    }

    static var accent: Color {
        Color(red: 0.10, green: 0.43, blue: 0.26)
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
        switch level {
        case 0:
            return Color.primary.opacity(0.055)
        case 1:
            return Color(red: 0.05, green: 0.27, blue: 0.16)
        case 2:
            return Color(red: 0.00, green: 0.43, blue: 0.20)
        case 3:
            return Color(red: 0.15, green: 0.65, blue: 0.25)
        default:
            return Color(red: 0.22, green: 0.83, blue: 0.33)
        }
    }
}
