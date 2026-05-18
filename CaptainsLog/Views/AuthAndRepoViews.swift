import SwiftUI
import Kit941

struct SetupWelcomeCard: View {
    let foundationAvailability: FoundationModelAvailability
    let preferredProvider: AIProvider
    let hasPreferredAIKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                Text("Captain's Log")
                    .kit941Font(.display, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("A private work journal built from the GitHub repositories you choose.")
                    .kit941Font(.body)
                    .foregroundStyle(AppSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetupHeatmapPreview()

            HStack(spacing: Kit941.Spacing.sm) {
                SetupCapabilityPill(title: "Selected repos", systemImage: "checklist")
                SetupCapabilityPill(title: "On device first", systemImage: "lock")
                SetupCapabilityPill(title: aiReadinessTitle, systemImage: aiReadinessSymbol)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Kit941.Spacing.lg)
        .appPanel(highlighted: true)
        .accessibilityElement(children: .contain)
    }

    private var aiReadinessTitle: String {
        if hasPreferredAIKey {
            return "\(preferredProvider.displayName) ready"
        }

        switch foundationAvailability {
        case .available:
            return "Apple summaries"
        case .unavailable:
            return "AI optional"
        }
    }

    private var aiReadinessSymbol: String {
        if hasPreferredAIKey {
            return preferredProvider.symbolName
        }

        switch foundationAvailability {
        case .available:
            return "apple.intelligence"
        case .unavailable:
            return "sparkles"
        }
    }
}

private struct SetupHeatmapPreview: View {
    private let levels: [Int] = [
        0, 1, 0, 0, 2, 3, 0, 0, 1, 4, 0, 2, 1,
        2, 0, 3, 1, 0, 2, 4, 0, 0, 1, 3, 0, 2,
        0, 2, 4, 3, 1, 0, 2, 1, 3, 4, 2, 0, 1
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack {
                Text("Work map preview")
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(AppSurface.secondaryText)
                Spacer(minLength: Kit941.Spacing.sm)
                Text("Commits + changes")
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.tertiaryText)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 13),
                alignment: .leading,
                spacing: 5
            ) {
                ForEach(levels.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppSurface.densityColor(level: levels[index]))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .padding(Kit941.Spacing.md)
        .background(AppSurface.mutedFill(opacity: 0.62), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
    }
}

private struct SetupCapabilityPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .kit941Font(.caption, weight: .semibold)
            .foregroundStyle(AppSurface.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppSurface.mutedFill(opacity: 0.86), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct GitHubAuthCard: View {
    @Environment(\.openURL) private var openURL

    let authState: AppModel.AuthState
    let clientID: String
    let authMessage: String
    let onConnect: @MainActor @Sendable () -> Void
    let onCompleteSignIn: @MainActor @Sendable () -> Void
    let onSeedDemo: @MainActor @Sendable () -> Void

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text(headline)
                    .kit941Font(.title, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)

                Text(description)
                    .kit941Font(.body)
                    .foregroundStyle(AppSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                stateContent

                VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                    actions
                }
            }
        }
    }

    private var headline: String {
        switch authState {
        case .waitingForUser, .completingSignIn:
            return "Finish GitHub sign-in"
        case .requestingCode:
            return "Getting a GitHub code"
        case .failed:
            return "Try GitHub again"
        case .signedOut, .signedIn:
            return "Choose your start"
        }
    }

    private var description: String {
        switch authState {
        case .waitingForUser, .completingSignIn:
            return "Use the code below to approve this device, then return here to continue."
        case .requestingCode:
            return "Captain's Log is asking GitHub for a short-lived device code."
        case .failed:
            return "GitHub did not finish connecting. You can try again or preview the app with demo data."
        case .signedOut, .signedIn:
            return "Connect GitHub to sync real work, or use demo data to inspect the app first."
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch authState {
        case .signedOut:
            if clientID.isEmpty {
                VStack(alignment: .leading, spacing: Kit941.Spacing.xs) {
                    Label("GitHub sign-in is not configured yet", systemImage: "exclamationmark.triangle")
                        .kit941Font(.label)
                        .foregroundStyle(AppSurface.warning)
                    Text("Register the GitHub App, enable Device Flow, and set GITHUB_CLIENT_ID in the build.")
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }
        case .requestingCode:
            Label("Requesting a GitHub code", systemImage: "hourglass")
                .kit941Font(.label)
                .foregroundStyle(AppSurface.secondaryText)
        case .waitingForUser(let code):
            codeContent(code, isChecking: false)
        case .completingSignIn(let code):
            codeContent(code, isChecking: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .kit941Font(.label)
                .foregroundStyle(AppSurface.danger)
        case .signedIn:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch authState {
        case .signedOut, .failed:
            AppActionRow(
                title: "Sign in with GitHub",
                description: "Authorize this device, then choose repositories.",
                systemImage: "person.crop.circle.badge.checkmark",
                isProminent: true,
                isDisabled: clientID.isEmpty,
                action: onConnect
            )

            AppActionRow(
                title: "Use Demo Data",
                description: "Preview the dashboard, work map, and journal.",
                systemImage: "square.grid.3x3",
                action: onSeedDemo
            )
        case .requestingCode:
            AppActionRow(
                title: "Requesting Code",
                description: "Waiting for GitHub to issue a device code.",
                systemImage: "hourglass",
                isProminent: true,
                isDisabled: true
            )
        case .waitingForUser(let code):
            AppActionRow(
                title: "Copy & Open GitHub",
                description: "Copy the device code, then open GitHub to authorize this app.",
                systemImage: "doc.on.doc",
                isProminent: true,
                action: {
                    ClipboardService.copy(code.userCode)
                    openURL(code.verificationURI)
                }
            )

            AppActionRow(
                title: "Check Authorization",
                description: "Return after approving the code in GitHub.",
                systemImage: "checkmark.circle",
                action: onCompleteSignIn
            )
        case .completingSignIn:
            AppActionRow(
                title: "Checking GitHub",
                description: "Completing authorization and saving the token.",
                systemImage: "hourglass",
                isProminent: true,
                isDisabled: true
            )
        case .signedIn:
            EmptyView()
        }
    }

    private func codeContent(_ code: GitHubDeviceCodeResponse, isChecking: Bool) -> some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text(code.userCode)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.sm)
                .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.md))
                .textSelection(.enabled)

            Text("Copy this code, authorize at github.com/login/device, then return and check authorization.")
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)

            if isChecking {
                Label("Checking GitHub authorization", systemImage: "hourglass")
                    .kit941Font(.label)
                    .foregroundStyle(AppSurface.secondaryText)
            } else if !authMessage.isEmpty {
                Label(authMessage, systemImage: "exclamationmark.triangle")
                    .kit941Font(.label)
                    .foregroundStyle(AppSurface.warning)
            }
        }
    }
}

struct RepositoryPanel: View {
    let repositories: [GitRepositoryRecord]
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let appInstallURL: URL?
    let onRefreshRepos: @MainActor @Sendable () -> Void
    let onSyncSelected: @MainActor @Sendable () -> Void
    let onFullSync: @MainActor @Sendable () -> Void
    let onInstallApp: @MainActor @Sendable () -> Void

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Repositories")
                            .kit941Font(.title, weight: .semibold)
                        Text(repositoryStatus)
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }

                    Spacer(minLength: Kit941.Spacing.sm)

                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if repositories.isEmpty {
                    VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                        Text("Approve access to all repositories or selected repositories in GitHub, then refresh.")
                            .kit941Font(.body)
                            .foregroundStyle(AppSurface.secondaryText)

                        if appInstallURL != nil {
                            AppActionRow(
                                title: "Approve Access",
                                description: "Open GitHub and choose which repositories this app can read.",
                                systemImage: "checklist",
                                action: onInstallApp
                            )
                        }
                    }
                } else {
                    NavigationLink {
                        RepositorySelectionView(
                            repositories: repositories,
                            appInstallURL: appInstallURL,
                            onRefreshRepos: onRefreshRepos,
                            onInstallApp: onInstallApp
                        )
                    } label: {
                        HStack(spacing: Kit941.Spacing.md) {
                            Image(systemName: "checklist")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppSurface.accent)
                                .frame(width: 38, height: 38)
                                .background(AppSurface.accent.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Manage selected repositories")
                                    .kit941Font(.label, weight: .semibold)
                                    .foregroundStyle(AppSurface.primaryText)
                                Text("Search, select all, or choose individual repositories.")
                                    .kit941Font(.caption)
                                    .foregroundStyle(AppSurface.secondaryText)
                            }

                            Spacer(minLength: Kit941.Spacing.sm)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppSurface.secondaryText)
                        }
                        .padding(12)
                        .background(AppSurface.mutedFill(opacity: 0.82), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if !syncMessage.isEmpty {
                    Text(syncMessage)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                    AppActionRow(
                        title: "Update Now",
                        description: "Pull recent commits and line stats for selected repositories.",
                        systemImage: "arrow.clockwise",
                        isProminent: true,
                        isDisabled: repositories.isEmpty || selectedCount == 0,
                        trailingText: latestWorkStatus,
                        action: onSyncSelected
                    )

                    AppActionRow(
                        title: "GitHub Access",
                        description: "Check which repositories Captain's Log can see.",
                        systemImage: "person.crop.circle.badge.checkmark",
                        trailingText: "\(repositories.count.formatted()) available",
                        action: onRefreshRepos
                    )

                    AppActionRow(
                        title: "History Coverage",
                        description: historyCoverageDescription,
                        systemImage: "clock.arrow.circlepath",
                        isDisabled: historyCoverageActionDisabled,
                        trailingText: historyCoverageStatus,
                        action: onFullSync
                    )
                }
            }
        }
    }

    private var selectedCount: Int {
        repositories.filter(\.isSelected).count
    }

    private var repositoryStatus: String {
        if repositories.isEmpty {
            return "No repositories loaded"
        }
        return "\(selectedCount) of \(repositories.count) selected"
    }

    private var selectedGitHubRepositories: [GitRepositoryRecord] {
        repositories.filter { $0.isSelected && $0.isGitHubBacked }
    }

    private var latestWorkStatus: String? {
        guard let latest = selectedGitHubRepositories.compactMap(\.lastSyncedAt).max() else {
            return nil
        }
        return latest.formatted(date: .omitted, time: .shortened)
    }

    private var historyCoverageStatus: String? {
        let selected = selectedGitHubRepositories
        guard !selected.isEmpty else {
            return nil
        }

        if isSyncing {
            return "Running"
        }

        let failedCount = selected.filter { $0.historyBackfillLastError != nil }.count
        if failedCount > 0 {
            return "\(failedCount.formatted()) paused"
        }

        let activeCount = selected.filter { $0.historyBackfillMonthStart != nil }.count
        if activeCount > 0 {
            return "\(activeCount.formatted()) active"
        }

        let completedCount = selected.filter(\.isHistoryBackfillComplete).count
        if completedCount == selected.count {
            return "Complete"
        }
        if completedCount > 0 {
            return "\(completedCount.formatted()) of \(selected.count.formatted())"
        }
        return "Not indexed"
    }

    private var historyCoverageDescription: String {
        let selected = selectedGitHubRepositories
        guard !selected.isEmpty else {
            return "Select repositories before indexing older history."
        }

        if let activeRepository = selected.first(where: { $0.historyBackfillMonthStart != nil }) {
            if let monthStart = activeRepository.historyBackfillMonthStart {
                let month = monthStart.formatted(.dateTime.month(.abbreviated).year())
                return "Indexing \(activeRepository.name) around \(month)."
            }
            return "Indexing \(activeRepository.name)."
        }

        if selected.contains(where: { $0.historyBackfillLastError != nil }) {
            return "Continue older commits and retry missing line stats."
        }

        if selected.allSatisfy(\.isHistoryBackfillComplete) {
            return "Older commits and line stats are indexed for selected repositories."
        }

        return "Continue older commits and missing line stats in batches."
    }

    private var historyCoverageActionDisabled: Bool {
        let selected = selectedGitHubRepositories
        guard !selected.isEmpty else {
            return true
        }
        return selected.allSatisfy(\.isHistoryBackfillComplete)
    }
}

struct AppActionRow: View {
    var title: String
    var description: String
    var systemImage: String
    var isProminent = false
    var isDestructive = false
    var isDisabled = false
    var trailingText: String?
    var showsChevron = true
    var action: @MainActor @Sendable () -> Void = {}

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: Kit941.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 38, height: 38)
                    .background(iconBackground, in: Circle())

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

                if let trailingText {
                    Text(trailingText)
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if showsChevron {
                    Image(systemName: isProminent ? "arrow.right" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.48 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityIdentifier("actionRow.\(title)")
    }

    private var iconColor: Color {
        if isDestructive {
            return AppSurface.warning
        }
        return isProminent ? AppSurface.background : AppSurface.accent
    }

    private var iconBackground: Color {
        if isDestructive {
            return AppSurface.warning.opacity(0.12)
        }
        return isProminent ? AppSurface.accent : AppSurface.accent.opacity(0.12)
    }

    private var rowBackground: Color {
        if isDestructive {
            return AppSurface.warning.opacity(0.08)
        }
        return isProminent ? AppSurface.accent.opacity(0.14) : AppSurface.mutedFill(opacity: 0.82)
    }

    private var rowStroke: Color {
        if isDestructive {
            return AppSurface.warning.opacity(0.22)
        }
        return isProminent ? AppSurface.accent.opacity(0.28) : AppSurface.panelStroke()
    }
}

private enum RepositoryListFilter: String, CaseIterable, Identifiable {
    case all
    case selected
    case unselected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .selected: "Selected"
        case .unselected: "Hidden"
        }
    }

    var emptyHeadline: String {
        switch self {
        case .all: "No repositories found"
        case .selected: "No selected repositories"
        case .unselected: "No hidden repositories"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: "Try a different repository name."
        case .selected: "Select repositories to include them in Captain's Log."
        case .unselected: "Clear a repository to hide it from the app."
        }
    }
}

struct RepositorySelectionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let repositories: [GitRepositoryRecord]
    let appInstallURL: URL?
    let onRefreshRepos: @MainActor @Sendable () -> Void
    let onInstallApp: @MainActor @Sendable () -> Void

    @State private var searchText = ""
    @State private var listFilter: RepositoryListFilter = .all

    var body: some View {
        ScrollView {
            content
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .appReadablePage(compactMaxWidth: 680, regularMaxWidth: 1080)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppSurface.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Repositories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: Kit941.Spacing.lg) {
                VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                    summaryCard
                    searchField
                }
                .frame(width: 360, alignment: .top)

                repositoryList
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                summaryCard
                searchField
                repositoryList
            }
        }
    }

    private var summaryCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectionSummary)
                        .kit941Font(.title, weight: .semibold)
                    Text(repositoryAvailability)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Picker("Repository filter", selection: $listFilter) {
                    ForEach(RepositoryListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: Kit941.Spacing.sm) {
                    RepositoryBulkButton(
                        title: "Select all available",
                        systemImage: "checkmark.circle",
                        action: { setAll(true) }
                    )
                    RepositoryBulkButton(
                        title: "Clear all",
                        systemImage: "xmark.circle",
                        action: { setAll(false) }
                    )
                }

                if appInstallURL != nil {
                    AppActionRow(
                        title: "Open GitHub Access",
                        description: "Add or remove the repositories this app is allowed to read.",
                        systemImage: "arrow.up.right.square",
                        action: onInstallApp
                    )
                }

                AppActionRow(
                    title: "Update List from GitHub",
                    description: "Reload repository access after changes in GitHub.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    action: onRefreshRepos
                )
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Kit941.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppSurface.secondaryText)

            TextField("Find repository", text: $searchText)
                .kit941Font(.body)
                .foregroundStyle(AppSurface.primaryText)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppSurface.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear repository search")
            }
        }
        .padding(.horizontal, Kit941.Spacing.md)
        .frame(minHeight: 48)
        .background(AppSurface.mutedFill(opacity: 0.9), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous)
                .strokeBorder(AppSurface.panelStroke(), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var repositoryList: some View {
        if filteredRepositories.isEmpty {
            Kit941.StatusView(
                style: .empty,
                symbol: "magnifyingglass",
                headline: LocalizedStringKey(listFilter.emptyHeadline),
                description: LocalizedStringKey(listFilter.emptyDescription)
            )
        } else {
            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(listTitle)
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)

                    Spacer(minLength: Kit941.Spacing.sm)

                    Text("\(filteredRepositories.count.formatted()) shown")
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(AppSurface.secondaryText)
                        .monospacedDigit()
                }
                .padding(.horizontal, Kit941.Spacing.xs)

                LazyVStack(spacing: 0) {
                    ForEach(filteredRepositories) { repo in
                        RepositoryToggleRow(repository: repo)
                        if repo.id != filteredRepositories.last?.id {
                            Divider()
                                .overlay(AppSurface.divider.opacity(0.55))
                        }
                    }
                }
                .appPanel()
            }
        }
    }

    private var filteredRepositories: [GitRepositoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedRepositories = repositories.filter { repository in
            switch listFilter {
            case .all:
                return true
            case .selected:
                return repository.isSelected
            case .unselected:
                return !repository.isSelected
            }
        }

        guard !query.isEmpty else {
            return scopedRepositories
        }
        return scopedRepositories.filter { repository in
            repository.fullName.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCount: Int {
        repositories.filter(\.isSelected).count
    }

    private var selectionSummary: String {
        if repositories.isEmpty {
            return "No repositories"
        }
        return "\(selectedCount.formatted()) of \(repositories.count.formatted()) selected"
    }

    private var repositoryAvailability: String {
        let unit = repositories.count == 1 ? "repository" : "repositories"
        return "\(repositories.count.formatted()) \(unit) available from GitHub"
    }

    private var listTitle: String {
        switch listFilter {
        case .all:
            return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All repositories" : "Search results"
        case .selected:
            return "Selected repositories"
        case .unselected:
            return "Not selected"
        }
    }

    private func setAll(_ isSelected: Bool) {
        for repository in repositories {
            repository.isSelected = isSelected
        }
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }
}

private struct RepositoryBulkButton: View {
    let title: String
    let systemImage: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .kit941Font(.caption, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, Kit941.Spacing.sm)
                .background(AppSurface.mutedFill(opacity: 0.74), in: RoundedRectangle(cornerRadius: Kit941.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Kit941.Radius.sm, style: .continuous)
                        .strokeBorder(AppSurface.panelStroke(), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppSurface.primaryText)
        .accessibilityIdentifier("repositoryBulk.\(title)")
    }
}

private struct RepositoryToggleRow: View {
    @Bindable var repository: GitRepositoryRecord

    var body: some View {
        Button {
            repository.isSelected.toggle()
        } label: {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.fullName)
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(repository.isPrivate ? "Private" : "Public")
                        if let pushedAt = repository.pushedAt {
                            Text("Updated \(pushedAt, style: .relative)")
                        }
                    }
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                }

                Spacer(minLength: Kit941.Spacing.md)

                Toggle("", isOn: .constant(repository.isSelected))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(repository.fullName)
        .accessibilityValue(repository.isSelected ? "Selected" : "Not selected")
    }
}
