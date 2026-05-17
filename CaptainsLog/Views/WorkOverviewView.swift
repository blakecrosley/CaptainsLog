import SwiftUI
import Kit941

struct GitRepositoryOverviewSnapshot {
    let repositoryCount: Int
    let selectedRepositoryCount: Int
    let coverage: [ActivityRepositoryCoverage]
    let historyIndexDetail: String?
    let lastSyncedAt: Date?

    init(repositories: [GitRepositoryRecord], now: Date = Date(), calendar: Calendar = .current) {
        repositoryCount = repositories.count
        selectedRepositoryCount = repositories.reduce(into: 0) { count, repository in
            if repository.isSelected {
                count += 1
            }
        }
        coverage = repositories.map { ActivityRepositoryCoverage(repository: $0, calendar: calendar) }

        let selectedRepositories = repositories.filter { $0.isSelected && $0.isGitHubBacked }
        lastSyncedAt = selectedRepositories.compactMap(\.lastSyncedAt).max()
        historyIndexDetail = Self.historyIndexDetail(
            for: selectedRepositories,
            coverage: coverage.filter { $0.isSelected && $0.isGitHubBacked },
            now: now,
            calendar: calendar
        )
    }

    private static func historyIndexDetail(
        for selectedRepositories: [GitRepositoryRecord],
        coverage selectedCoverage: [ActivityRepositoryCoverage],
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard !selectedRepositories.isEmpty else {
            return nil
        }

        if ActivityDataTrust.state(
            for: now,
            selectedRepositoryCoverage: selectedCoverage,
            now: now,
            calendar: calendar
        ) == .unknown {
            return "Today has not been refreshed"
        }

        if let activeRepository = selectedRepositories.first(where: { $0.historyBackfillMonthStart != nil }) {
            if let monthStart = activeRepository.historyBackfillMonthStart {
                let month = monthStart.formatted(.dateTime.month(.abbreviated).year())
                return "Indexing history: \(activeRepository.name) \(month)"
            }
            return "Indexing history: \(activeRepository.name)"
        }

        let failedCount = selectedRepositories.filter { $0.historyBackfillLastError != nil }.count
        if failedCount > 0 {
            let unit = failedCount == 1 ? "repo" : "repos"
            return "History index paused on \(failedCount.formatted()) \(unit)"
        }

        let completedCount = selectedRepositories.filter(\.isHistoryBackfillComplete).count
        guard completedCount > 0, completedCount < selectedRepositories.count else {
            return nil
        }
        return "History index \(completedCount.formatted()) of \(selectedRepositories.count.formatted()) repositories complete"
    }
}

struct WorkOverviewView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedDate: Date
    @Binding var displayMetric: WorkDisplayMetric

    let workMetrics: WorkMetrics
    let selectedWorkSnapshot: DayWorkSnapshot
    let selectedSummary: DailyJournalSummaryRecord?
    let repositorySnapshot: GitRepositoryOverviewSnapshot
    let githubLogin: String?
    let githubAvatarURL: URL?
    let isGitHubSignedIn: Bool
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let updatedDiffStatCount: Int
    let workIdentityScope: WorkIdentityScope
    let identityAliasCount: Int
    let onShowAccounts: @MainActor @Sendable () -> Void
    let onSyncLatest: @MainActor @Sendable () -> Void
    let onFillLineStats: @MainActor @Sendable (WorkRangeScope, DateInterval) -> Void
    let onShowSettings: @MainActor @Sendable () -> Void
    let onShowMonth: @MainActor @Sendable () -> Void
    let onShowDayDetail: @MainActor @Sendable () -> Void

    @State private var selectedScope: WorkRangeScope = .week
    @State private var isShowingWorkAnalytics = false
    @State private var isShowingActivityMap = false
    @State private var isShowingSyncStatus = false
    #if DEBUG
    @State private var didPresentDebugScreenshotRoute = false
    @State private var isShowingDebugActivityMap = false
    #endif

    var body: some View {
        dashboardContent
        .sheet(isPresented: $isShowingWorkAnalytics) {
            WorkAnalyticsSheet(
                selectedDate: selectedDate,
                workMetrics: workMetrics,
                scope: $selectedScope,
                metric: displayMetric,
                isSyncing: isSyncing,
                canFillLineStats: isGitHubSignedIn,
                onFillLineStats: onFillLineStats
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingActivityMap) {
            WorkMapDetailSheet(
                selectedDate: $selectedDate,
                workMetrics: workMetrics,
                repositoryCoverage: repositorySnapshot.coverage,
                metric: displayMetric
            )
            .presentationDetents([.large])
        }
        #if DEBUG
        .fullScreenCover(isPresented: $isShowingDebugActivityMap) {
            WorkMapDetailSheet(
                selectedDate: $selectedDate,
                workMetrics: workMetrics,
                repositoryCoverage: repositorySnapshot.coverage,
                metric: displayMetric
            )
        }
        .onAppear {
            presentDebugScreenshotRouteIfNeeded()
        }
        #endif
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if usesWideDashboard {
            wideDashboardContent
        } else {
            compactDashboardContent
        }
    }

    private var compactDashboardContent: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.xl) {
            overviewHeader
            weekStrip
            WorkLensControl(metric: $displayMetric)
            activityMap
            periodSnapshot
            selectedDayAnnotation
        }
    }

    private var wideDashboardContent: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.xl) {
            overviewHeader
            weekStrip

            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                WorkLensControl(metric: $displayMetric)
                    .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Kit941.Spacing.lg) {
                activityMap
                    .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    periodSnapshot
                    selectedDayAnnotation
                }
                .frame(width: 360, alignment: .top)
            }
        }
    }

    private var usesWideDashboard: Bool {
        horizontalSizeClass == .regular
    }

    private var weekStrip: some View {
        JournalWeekStrip(
            selectedDate: $selectedDate,
            workMetrics: workMetrics,
            onShowMonth: onShowMonth
        )
    }

    private var activityMap: some View {
        ActivityHeatmapView(
            selectedDate: $selectedDate,
            workMetrics: workMetrics,
            repositoryCoverage: repositorySnapshot.coverage,
            metric: displayMetric,
            onShowDetail: { isShowingActivityMap = true }
        )
    }

    private var periodSnapshot: some View {
        PeriodSnapshotCard(
            trend: trend,
            summary: rangeSummary,
            scope: $selectedScope,
            metric: displayMetric,
            onOpen: { isShowingWorkAnalytics = true }
        )
    }

    private var selectedDayAnnotation: some View {
        SelectedDayAnnotationRow(
            selectedDate: selectedDate,
            snapshot: selectedWorkSnapshot,
            metric: displayMetric,
            summary: selectedSummary,
            onShowDayDetail: onShowDayDetail
        )
    }

    private var trend: WorkTrendSummary {
        workMetrics.trend(scope: selectedScope, containing: selectedDate)
    }

    private var rangeSummary: WorkRangeSummary {
        workMetrics.rangeSummary(scope: selectedScope, containing: selectedDate)
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .center, spacing: Kit941.Spacing.sm) {
                Button {
                    onShowAccounts()
                } label: {
                    HStack(spacing: 10) {
                        GitHubAvatarView(url: githubAvatarURL, login: githubLogin)
                            .frame(width: 34, height: 34)

                        Text(accountTitle)
                            .kit941Font(.title, weight: .semibold)
                            .foregroundStyle(AppSurface.primaryText)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch GitHub account")

                Spacer(minLength: Kit941.Spacing.sm)

                HStack(spacing: Kit941.Spacing.xs) {
                    if isGitHubSignedIn {
                        SyncStatusButton(
                            repositoryCount: repositorySnapshot.repositoryCount,
                            selectedRepositoryCount: repositorySnapshot.selectedRepositoryCount,
                            isSyncing: isSyncing,
                            syncMessage: syncMessage,
                            historyIndexDetail: repositorySnapshot.historyIndexDetail,
                            lastSyncedAt: repositorySnapshot.lastSyncedAt,
                            action: {
                                isShowingSyncStatus = true
                            }
                        )
                        .popover(isPresented: $isShowingSyncStatus, arrowEdge: .top) {
                            SyncStatusPopover(
                                repositoryCount: repositorySnapshot.repositoryCount,
                                selectedRepositoryCount: repositorySnapshot.selectedRepositoryCount,
                                isSyncing: isSyncing,
                                syncMessage: syncMessage,
                                importedCommitCount: importedCommitCount,
                                updatedDiffStatCount: updatedDiffStatCount,
                                lastSyncedAt: repositorySnapshot.lastSyncedAt,
                                historyIndexDetail: repositorySnapshot.historyIndexDetail,
                                workIdentityScope: workIdentityScope,
                                identityAliasCount: identityAliasCount,
                                onSyncLatest: {
                                    isShowingSyncStatus = false
                                    onSyncLatest()
                                },
                                onShowSettings: {
                                    isShowingSyncStatus = false
                                    onShowSettings()
                                }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    } else {
                        iconButton("Sign in with GitHub", systemImage: "person.crop.circle.badge.plus", action: onShowAccounts)
                    }
                    iconButton("Settings", systemImage: "gearshape", action: onShowSettings)
                }
            }
        }
    }

    private var accountTitle: String {
        if let githubLogin {
            return githubLogin
        }
        return "GitHub"
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppSurface.primaryText)
                .frame(width: 38, height: 38)
                .background(AppSurface.mutedFill(opacity: 1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    #if DEBUG
    @MainActor
    private func presentDebugScreenshotRouteIfNeeded() {
        guard !didPresentDebugScreenshotRoute,
              ProcessInfo.processInfo.environment["CAPTAINS_LOG_SCREENSHOT_ROUTE"] == "work-map" else {
            return
        }

        didPresentDebugScreenshotRoute = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            isShowingDebugActivityMap = true
        }
    }
    #endif
}

private struct SyncStatusButton: View {
    let repositoryCount: Int
    let selectedRepositoryCount: Int
    let isSyncing: Bool
    let syncMessage: String
    let historyIndexDetail: String?
    let lastSyncedAt: Date?
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(AppSurface.mutedFill(opacity: 1))
                    .frame(width: 38, height: 38)

                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppSurface.accent)
                        .frame(width: 38, height: 38)
                } else {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 38, height: 38)
                }

                if needsAttention {
                    Circle()
                        .fill(AppSurface.warning)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(AppSurface.background, lineWidth: 1.5)
                        )
                        .offset(x: -2, y: 2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("GitHub sync status")
        .accessibilityValue(accessibilityValue)
    }

    private var statusSymbol: String {
        if needsAttention {
            return "exclamationmark.triangle.fill"
        }
        if lastSyncedAt != nil {
            return "checkmark"
        }
        return "arrow.clockwise"
    }

    private var iconColor: Color {
        needsAttention ? AppSurface.warning : AppSurface.primaryText
    }

    private var needsAttention: Bool {
        selectedRepositoryCount == 0 || isErrorMessage || historyIndexDetail?.localizedCaseInsensitiveContains("paused") == true
    }

    private var isErrorMessage: Bool {
        let lowered = syncMessage.lowercased()
        return lowered.contains("failed")
            || lowered.contains("error")
            || lowered.contains("unauthorized")
            || lowered.contains("401")
            || lowered.contains("404")
    }

    private var accessibilityValue: String {
        if isSyncing {
            return syncMessage.isEmpty ? "Syncing GitHub" : syncMessage
        }
        if selectedRepositoryCount == 0 {
            return "No repositories selected"
        }
        if let historyIndexDetail {
            return historyIndexDetail
        }
        if let lastSyncedAt {
            return "Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(selectedRepositoryCount.formatted()) of \(repositoryCount.formatted()) repositories selected"
    }
}

private struct SyncStatusPopover: View {
    let repositoryCount: Int
    let selectedRepositoryCount: Int
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let updatedDiffStatCount: Int
    let lastSyncedAt: Date?
    let historyIndexDetail: String?
    let workIdentityScope: WorkIdentityScope
    let identityAliasCount: Int
    let onSyncLatest: @MainActor @Sendable () -> Void
    let onShowSettings: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .center, spacing: Kit941.Spacing.sm) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .kit941Font(.title, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                    Text(detail)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statusNote {
                Text(statusNote)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Kit941.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Kit941.Spacing.xs) {
                detailRow("Repositories", value: repositoryDetail)
                detailRow("Latest run", value: latestRunDetail)
                detailRow("History", value: historyDetail)
                detailRow("Work scope", value: workScopeLabel)
            }

            VStack(spacing: Kit941.Spacing.xs) {
                popoverAction("Update now", systemImage: "arrow.clockwise", isDisabled: selectedRepositoryCount == 0, action: onSyncLatest)
                popoverAction("Sync settings", systemImage: "slider.horizontal.3", action: onShowSettings)
            }
        }
        .padding(Kit941.Spacing.lg)
        .frame(width: 320, alignment: .leading)
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(AppSurface.accent.opacity(0.12))
                .frame(width: 38, height: 38)

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppSurface.accent)
            } else {
                Image(systemName: statusSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var title: String {
        if isSyncing {
            return "Syncing GitHub"
        }
        return repositoryCount > 0 ? "GitHub history" : "GitHub connected"
    }

    private var detail: String {
        if isSyncing {
            return syncMessage.isEmpty ? "Syncing GitHub" : syncMessage
        }
        if selectedRepositoryCount == 0 {
            return "Choose repositories before Captain's Log can update the dashboard."
        }
        if let historyIndexDetail {
            return historyIndexDetail
        }
        if let lastSyncedAt {
            return "Last updated \(lastSyncedAt.formatted(date: .omitted, time: .shortened))."
        }
        return "Ready to update latest work."
    }

    private var statusNote: String? {
        if isSyncing {
            return "You can keep using the app while this runs. The dashboard updates after batches finish."
        }

        if selectedRepositoryCount == 0 {
            return "Open sync settings to choose repositories, then update latest work."
        }

        guard let historyIndexDetail else {
            if lastSyncedAt != nil {
                return "Use Update now after committing new work; it checks recent commits before older history."
            }
            return "Update now checks recent commits first. Older history can continue in the background."
        }

        let lowered = historyIndexDetail.lowercased()
        if lowered.contains("today") {
            return "Update now checks today's commits first, then fills older history and missing line stats separately."
        }
        if lowered.contains("indexing") {
            return "Older months are being backfilled in small batches so the main screen stays usable."
        }
        if lowered.contains("paused") {
            return "Open sync settings to retry indexing or refresh GitHub repository access."
        }
        if lowered.contains("complete") {
            return "Some selected repositories are fully indexed; the remaining repositories will continue in later batches."
        }
        return nil
    }

    private var repositoryDetail: String {
        if repositoryCount == 0 {
            return "No repositories loaded"
        }
        return "\(selectedRepositoryCount.formatted()) of \(repositoryCount.formatted()) selected"
    }

    private var latestRunDetail: String {
        if importedCommitCount > 0 || updatedDiffStatCount > 0 {
            return "\(importedCommitCount.formatted()) commits, \(updatedDiffStatCount.formatted()) diff stats this run"
        }
        if let lastSyncedAt {
            return "Last sync \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Not synced yet"
    }

    private var historyDetail: String {
        historyIndexDetail ?? "No older-history backfill running"
    }

    private var workScopeLabel: String {
        switch workIdentityScope {
        case .allSelectedRepos:
            return workIdentityScope.label
        case .mineAndAliases:
            if identityAliasCount > 0 {
                return "\(workIdentityScope.label): \(identityAliasCount.formatted()) extra"
            }
            return workIdentityScope.label
        }
    }

    private var statusSymbol: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        if selectedRepositoryCount == 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var statusColor: Color {
        selectedRepositoryCount == 0 ? AppSurface.warning : AppSurface.accent
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Kit941.Spacing.md) {
            Text(label)
                .kit941Font(.caption, weight: .semibold)
                .foregroundStyle(AppSurface.secondaryText)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func popoverAction(
        _ title: String,
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: Kit941.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .kit941Font(.label, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDisabled ? AppSurface.secondaryText : AppSurface.primaryText)
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct WorkLensControl: View {
    @Binding var metric: WorkDisplayMetric

    var body: some View {
        Picker("Work lens", selection: $metric) {
            ForEach(WorkDisplayMetric.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Work lens")
        .accessibilityValue(metric.title)
    }
}

private struct WorkLensContextRow: View {
    let metric: WorkDisplayMetric
    let summary: WorkRangeSummary

    var body: some View {
        HStack(alignment: .center, spacing: Kit941.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(metric.title) lens")
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)
                Text(dataBasisLabel)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: Kit941.Spacing.sm)

            if metric == .changes && summary.commitCount > 0 {
                DataConfidenceMark(summary: summary)
            }
        }
        .padding(.horizontal, Kit941.Spacing.md)
        .padding(.vertical, 10)
        .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var dataBasisLabel: String {
        guard summary.commitCount > 0 else {
            return "No imported work"
        }
        switch metric {
        case .commits:
            return "GitHub commits from selected repositories"
        case .changes:
            guard summary.statsBackedCommitCount > 0 else {
                return "Waiting for changed-line stats"
            }
            let backed = summary.statsBackedCommitCount.formatted()
            let total = summary.commitCount.formatted()
            if summary.isDiffStatsComplete {
                return "Complete changed-line stats: \(backed) of \(total)"
            }
            return "Partial changed-line stats: \(backed) of \(total)"
        }
    }
}

private struct WorkLensPill: View {
    let metric: WorkDisplayMetric

    var body: some View {
        Text(metric.title)
            .kit941Font(.caption, weight: .semibold)
            .foregroundStyle(AppSurface.primaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppSurface.mutedFill(opacity: 1), in: Capsule())
    }
}

private struct PeriodSnapshotCard: View {
    let trend: WorkTrendSummary
    let summary: WorkRangeSummary
    @Binding var scope: WorkRangeScope
    let metric: WorkDisplayMetric
    let onOpen: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected \(scope.lowerTitle)")
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.secondaryText)
                    Text(dateRangeLabel)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Spacer(minLength: 0)
            }

            Picker("Period", selection: $scope) {
                ForEach(WorkRangeScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric.value(for: summary).formatted())
                        .font(AppSurface.metricFont(size: 58))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(primaryUnitLabel)
                        .kit941Font(.title)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                if metric == .changes {
                    ChangeBalanceRail(summary: summary)
                } else {
                    CommitContextRail(summary: summary)
                }
            }

            HStack(spacing: Kit941.Spacing.sm) {
                ComparisonBadge(
                    label: comparisonBadgeLabel,
                    symbolName: metricDirection.symbolName,
                    color: directionColor
                )

                Spacer(minLength: Kit941.Spacing.sm)

                DashboardFactPill(text: secondaryMetricLabel)

                if metric == .changes {
                    DataConfidenceMark(summary: summary)
                }
            }
        }
        .padding(Kit941.Spacing.md)
        .appPanel(highlighted: true)
        .contentShape(RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .onTapGesture {
            onOpen()
        }
        .accessibilityAddTraits(.isButton)
    }

    private var dateRangeLabel: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: summary.end) ?? summary.end
        switch scope {
        case .day:
            return summary.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .month:
            return summary.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return summary.start.formatted(.dateTime.year())
        case .week:
            if calendar.isDate(summary.start, inSameDayAs: end) {
                return summary.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
            return "\(summary.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private var comparisonBadgeLabel: String {
        switch metricDirection {
        case .up:
            return "above last \(scope.lowerTitle)"
        case .down:
            return "below last \(scope.lowerTitle)"
        case .steady:
            return "steady"
        case .noBaseline:
            return "baseline"
        }
    }

    private var primaryUnitLabel: String {
        switch metric {
        case .changes:
            return summary.isDiffStatsComplete ? "lines touched" : "known lines touched"
        case .commits:
            return summary.commitCount == 1 ? "commit" : "commits"
        }
    }

    private var secondaryMetricLabel: String {
        switch metric {
        case .changes:
            return "\(summary.commitCount.formatted()) commits"
        case .commits:
            guard summary.statsBackedCommitCount > 0 else {
                return "Line stats pending"
            }
            return "\(summary.totalChanges.formatted()) known lines"
        }
    }

    private var metricPercentChange: Double? {
        guard metric.canCompare(summary, trend.baseline) else {
            return nil
        }
        let baseline = metric.averagePerDay(for: trend.baseline)
        guard baseline > 0 else {
            return nil
        }
        return (metric.averagePerDay(for: summary) - baseline) / baseline
    }

    private var metricDirection: WorkTrendDirection {
        guard let metricPercentChange else {
            return .noBaseline
        }
        if metricPercentChange > 0.10 {
            return .up
        }
        if metricPercentChange < -0.10 {
            return .down
        }
        return .steady
    }

    private var directionColor: Color {
        switch metricDirection {
        case .up: AppSurface.accent
        case .steady: AppSurface.secondaryText
        case .down: AppSurface.warning
        case .noBaseline: AppSurface.secondaryText
        }
    }
}

private struct ChangeBalanceRail: View {
    let summary: WorkRangeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let availableWidth = max(proxy.size.width - spacing, 1)
                let additionWidth = segmentWidth(summary.additions, totalWidth: availableWidth)
                HStack(spacing: spacing) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(additionColor)
                        .frame(width: additionWidth)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(deletionColor)
                        .frame(width: max(availableWidth - additionWidth, 0))
                }
            }
            .frame(height: 10)
            .opacity(hasLineStats ? 1 : 0.45)

            HStack(spacing: Kit941.Spacing.sm) {
                BalanceToken(text: "+\(summary.additions.formatted())", color: additionColor)
                BalanceToken(text: "-\(summary.deletions.formatted())", color: deletionColor)
                Spacer(minLength: Kit941.Spacing.xs)
                DashboardFactPill(text: filesLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var hasLineStats: Bool {
        summary.statsBackedCommitCount > 0
    }

    private var totalLines: Int {
        summary.additions + summary.deletions
    }

    private var additionColor: Color {
        hasLineStats ? AppSurface.accent : AppSurface.track.opacity(0.78)
    }

    private var deletionColor: Color {
        hasLineStats ? AppSurface.secondaryAccent : AppSurface.track.opacity(0.56)
    }

    private var filesLabel: String {
        let unit = summary.changedFiles == 1 ? "file" : "files"
        return "\(summary.changedFiles.formatted()) \(unit)"
    }

    private var accessibilityLabel: String {
        guard hasLineStats else {
            return "Changed-line stats pending"
        }
        return "\(summary.additions) additions, \(summary.deletions) deletions, \(summary.changedFiles) changed files"
    }

    private func segmentWidth(_ value: Int, totalWidth: CGFloat) -> CGFloat {
        guard hasLineStats, totalLines > 0 else {
            return totalWidth / 2
        }
        return totalWidth * CGFloat(value) / CGFloat(totalLines)
    }
}

private struct CommitContextRail: View {
    let summary: WorkRangeSummary

    var body: some View {
        HStack(spacing: Kit941.Spacing.sm) {
            DashboardFactPill(text: linesLabel)
            DashboardFactPill(text: filesLabel)
            Spacer(minLength: 0)
        }
    }

    private var linesLabel: String {
        guard summary.statsBackedCommitCount > 0 else {
            return "line stats pending"
        }
        return "\(summary.totalChanges.formatted()) known lines"
    }

    private var filesLabel: String {
        guard summary.changedFiles > 0 else {
            return "files pending"
        }
        let unit = summary.changedFiles == 1 ? "file" : "files"
        return "\(summary.changedFiles.formatted()) \(unit)"
    }
}

private struct BalanceToken: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .kit941Font(.caption, weight: .semibold)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct ComparisonBadge: View {
    let label: String
    let symbolName: String
    let color: Color

    var body: some View {
        Label(label, systemImage: symbolName)
            .kit941Font(.caption, weight: .semibold)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct DashboardFactPill: View {
    let text: String

    var body: some View {
        Text(text)
            .kit941Font(.caption, weight: .semibold)
            .foregroundStyle(AppSurface.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppSurface.mutedFill(opacity: 1), in: Capsule())
    }
}

private struct DataConfidenceMark: View {
    let summary: WorkRangeSummary

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppSurface.track, lineWidth: 2.3)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(summary.coverage, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if summary.isDiffStatsComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        summary.isDiffStatsComplete ? AppSurface.accent : AppSurface.warning
    }

    private var accessibilityLabel: String {
        if summary.isDiffStatsComplete {
            return "Complete line stats"
        }
        return "\(summary.coverage.formatted(.percent.precision(.fractionLength(0)))) line stats coverage"
    }
}

private enum WorkBreakdownDimension: String, CaseIterable, Identifiable {
    case type
    case language

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: "Type"
        case .language: "Language"
        }
    }
}

private struct WorkAnalyticsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedDate: Date
    let workMetrics: WorkMetrics
    @Binding var scope: WorkRangeScope
    let metric: WorkDisplayMetric
    let isSyncing: Bool
    let canFillLineStats: Bool
    let onFillLineStats: @MainActor @Sendable (WorkRangeScope, DateInterval) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    controls
                    headline
                    trendPanel
                    if metric == .changes && summary.commitCount > 0 {
                        DataCoverageBar(summary: summary)
                            .padding(Kit941.Spacing.md)
                            .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
                    }
                    if shouldShowLineStatsAction {
                        lineStatsAction
                    }
                    breakdownPanels
                    statsPanel
                }
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .appReadablePage(compactMaxWidth: 720, regularMaxWidth: 860)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Work")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            Picker("Period", selection: $scope) {
                ForEach(WorkRangeScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            WorkLensContextRow(metric: metric, summary: summary)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.title)
                        .kit941Font(.title, weight: .semibold)
                    Text(dateRangeLabel)
                        .kit941Font(.body)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Spacer(minLength: Kit941.Spacing.md)

                Label(comparisonLabel, systemImage: metricDirection.symbolName)
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(directionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.value(for: summary).formatted())
                    .font(AppSurface.metricFont(size: 58))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(metric.unit(for: summary))
                    .kit941Font(.title)
                    .foregroundStyle(AppSurface.secondaryText)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
            }

            if summary.statsBackedCommitCount > 0 {
                Text("+\(summary.additions.formatted()) -\(summary.deletions.formatted()) across \(summary.changedFiles.formatted()) files")
                    .kit941Font(.body)
                    .foregroundStyle(AppSurface.secondaryText)
            }
        }
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack {
                Text("Timeline")
                    .kit941Font(.label, weight: .semibold)
                Spacer()
                Text("Last \(trendSummaries.count) \(scope.pluralTitle)")
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
            }

            PeriodBarTrendView(
                summaries: trendSummaries,
                scope: scope,
                metric: metric
            )
            .frame(height: 156)

            Text("Each bar is one \(scope.lowerTitle). The bright bar is the selected \(scope.lowerTitle).")
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)

            if canShowComparisonMark {
                ComparisonMarkView(
                    currentAverage: metric.averagePerDay(for: summary),
                    baselineAverage: metric.averagePerDay(for: trend.baseline),
                    unit: metric.shortUnit
                )
                .frame(height: 46)
            }
        }
        .padding(Kit941.Spacing.md)
        .appPanel()
    }

    private var lineStatsAction: some View {
        HStack(spacing: Kit941.Spacing.sm) {
            Label(lineStatsStatusLabel, systemImage: lineStatsSymbol)
                .kit941Font(.caption, weight: .semibold)
                .foregroundStyle(summary.isDiffStatsComplete ? AppSurface.accent : AppSurface.warning)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                onFillLineStats(scope, DateInterval(start: summary.start, end: summary.end))
            } label: {
                Label(lineStatsButtonLabel, systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSyncing)
        }
        .padding(Kit941.Spacing.md)
        .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
    }

    private var breakdownPanels: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            BreakdownPanel(title: "Type", summary: summary, dimension: .type)
            BreakdownPanel(title: "Language", summary: summary, dimension: .language)
        }
    }

    private var statsPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Kit941.Spacing.sm), count: 3), spacing: Kit941.Spacing.sm) {
            StatTile(label: "Commits", value: summary.commitCount.formatted())
            StatTile(label: "Files", value: summary.changedFiles.formatted())
            StatTile(label: "Coverage", value: summary.coverage.formatted(.percent.precision(.fractionLength(0))))
            StatTile(label: "Additions", value: "+\(summary.additions.formatted())")
            StatTile(label: "Deletions", value: "-\(summary.deletions.formatted())")
            StatTile(label: "Days", value: summary.dayCount.formatted())
        }
    }

    private var trend: WorkTrendSummary {
        workMetrics.trend(scope: scope, containing: selectedDate)
    }

    private var summary: WorkRangeSummary {
        workMetrics.rangeSummary(scope: scope, containing: selectedDate)
    }

    private var trendSummaries: [WorkRangeSummary] {
        (0..<scope.trendPointCount).reversed().compactMap { offset in
            guard let date = date(byAddingPeriods: -offset, to: selectedDate, scope: scope) else {
                return nil
            }
            return workMetrics.rangeSummary(scope: scope, containing: date)
        }
    }

    private var dateRangeLabel: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: summary.end) ?? summary.end
        switch scope {
        case .day:
            return summary.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .month:
            return summary.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return summary.start.formatted(.dateTime.year())
        case .week:
            if calendar.isDate(summary.start, inSameDayAs: end) {
                return summary.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
            return "\(summary.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private var comparisonLabel: String {
        guard let percentChange = metricPercentChange else {
            return "Building baseline"
        }
        let formatted = percentChange.formatted(.percent.precision(.fractionLength(0)))
        let signed = percentChange > 0 ? "+\(formatted)" : formatted
        return "\(signed) vs prior \(scope.lowerTitle)"
    }

    private var metricPercentChange: Double? {
        guard metric.canCompare(summary, trend.baseline) else {
            return nil
        }
        let baseline = metric.averagePerDay(for: trend.baseline)
        guard baseline > 0 else {
            return nil
        }
        return (metric.averagePerDay(for: summary) - baseline) / baseline
    }

    private var canShowComparisonMark: Bool {
        metric.canCompare(summary, trend.baseline) && metric.averagePerDay(for: trend.baseline) > 0
    }

    private var metricDirection: WorkTrendDirection {
        guard let metricPercentChange else {
            return .noBaseline
        }
        if metricPercentChange > 0.10 {
            return .up
        }
        if metricPercentChange < -0.10 {
            return .down
        }
        return .steady
    }

    private var directionColor: Color {
        switch metricDirection {
        case .up: AppSurface.accent
        case .steady: AppSurface.secondaryText
        case .down: AppSurface.warning
        case .noBaseline: AppSurface.secondaryText
        }
    }

    private var shouldShowLineStatsAction: Bool {
        metric == .changes && canFillLineStats && summary.missingDiffStatsCount > 0
    }

    private var lineStatsStatusLabel: String {
        guard summary.commitCount > 0 else {
            return "Fetch GitHub history for this \(scope.lowerTitle)"
        }
        guard summary.missingDiffStatsCount > 0 else {
            return "Line stats ready for this \(scope.lowerTitle)"
        }
        let count = summary.missingDiffStatsCount
        let unit = count == 1 ? "commit" : "commits"
        return "Partial data: \(count.formatted()) \(unit) missing"
    }

    private var lineStatsSymbol: String {
        summary.isDiffStatsComplete ? "checkmark.seal" : "exclamationmark.triangle"
    }

    private var lineStatsButtonLabel: String {
        if summary.missingDiffStatsCount > 0 {
            return "Fill \(scope.title)"
        }
        return "Refresh \(scope.title)"
    }

    private func date(byAddingPeriods value: Int, to date: Date, scope: WorkRangeScope) -> Date? {
        let calendar = Calendar.current
        switch scope {
        case .day:
            return calendar.date(byAdding: .day, value: value, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date)
        case .year:
            return calendar.date(byAdding: .year, value: value, to: date)
        }
    }
}

private struct WorkMapDetailSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let repositoryCoverage: [ActivityRepositoryCoverage]
    let metric: WorkDisplayMetric
    @State private var selectedMapYear: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .appReadablePage(compactMaxWidth: 720, regularMaxWidth: 900)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Work Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            header
            ActivityHeatmapView(
                selectedDate: $selectedDate,
                workMetrics: workMetrics,
                repositoryCoverage: repositoryCoverage,
                metric: metric,
                selectedYear: $selectedMapYear,
                showsHeaderTitle: false
            )

            if usesWideLayout {
                HStack(alignment: .top, spacing: Kit941.Spacing.lg) {
                    WorkMapDayInspector(selectedDate: selectedDate, insight: dayInsight, metric: metric)
                    WorkMapRhythmPanel(insights: periodInsights, metric: metric)
                }
            } else {
                WorkMapDayInspector(selectedDate: selectedDate, insight: dayInsight, metric: metric)
                WorkMapRhythmPanel(insights: periodInsights, metric: metric)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateRangeLabel)
                        .kit941Font(.label, weight: .semibold)
                    Text(headerSubtitle)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Spacer(minLength: Kit941.Spacing.sm)

                WorkLensPill(metric: metric)
            }
        }
    }

    private var dayInsight: WorkMapDayInsight {
        workMetrics.workMapDayInsight(on: selectedDate)
    }

    private var periodInsights: WorkMapPeriodInsights {
        workMetrics.workMapPeriodInsights(
            interval: mapInterval,
            selectedDate: selectedDate,
            metric: metric
        )
    }

    private var dateRangeLabel: String {
        let calendar = Calendar.current
        guard let selectedMapYear else {
            let end = calendar.date(byAdding: .day, value: -1, to: mapInterval.end) ?? mapInterval.end
            return "\(mapInterval.start.formatted(.dateTime.month(.abbreviated).day().year())) - \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return "\(selectedMapYear)"
    }

    private var headerSubtitle: String {
        let summary = periodInsights.summary
        switch metric {
        case .changes:
            guard summary.commitCount > 0 else {
                return "No imported work in this map range."
            }
            if summary.isDiffStatsComplete {
                return "\(summary.totalChanges.formatted()) changed lines across \(activeDayCountLabel)"
            }
            return "\(summary.totalChanges.formatted()) known lines. \(summary.coverage.formatted(.percent.precision(.fractionLength(0)))) stats coverage"
        case .commits:
            return "\(summary.commitCount.formatted()) commits across \(activeDayCountLabel)"
        }
    }

    private var activeDayCountLabel: String {
        let count = periodInsights.activeDayCount
        let unit = count == 1 ? "active day" : "active days"
        return "\(count.formatted()) \(unit)"
    }

    private var mapInterval: DateInterval {
        let calendar = Calendar.current
        if let selectedMapYear,
           let start = calendar.date(from: DateComponents(year: selectedMapYear, month: 1, day: 1)),
           let end = calendar.date(byAdding: .year, value: 1, to: start) {
            return DateInterval(start: start, end: end)
        }

        let weeks = CalendarMath.contributionWeeks(ending: Date(), weekCount: 52, calendar: calendar)
        let start = weeks.first?.first ?? calendar.startOfDay(for: Date())
        let lastDay = weeks.last?.last ?? calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }
}

private struct BreakdownPanel: View {
    let title: String
    let summary: WorkRangeSummary
    let dimension: WorkBreakdownDimension

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            Text(title)
                .kit941Font(.label, weight: .semibold)
            WorkBreakdownStrip(summary: summary, dimension: dimension)
        }
        .padding(Kit941.Spacing.md)
        .appPanel()
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .kit941Font(.title, weight: .semibold)
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(label)
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kit941.Spacing.md)
        .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
    }
}

private struct WorkMapDayInspector: View {
    let selectedDate: Date
    let insight: WorkMapDayInsight
    let metric: WorkDisplayMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .kit941Font(.title, weight: .semibold)
                    Text(statusLabel)
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 0)

                DashboardFactPill(text: "\(insight.repositoryCount.formatted()) repos")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(primaryValue)
                    .font(AppSurface.metricFont(size: 54))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(primaryUnit)
                    .kit941Font(.title)
                    .foregroundStyle(AppSurface.secondaryText)
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)
            }

            WorkMapBalanceRail(
                additions: insight.snapshot.additions,
                deletions: insight.snapshot.deletions,
                changedFiles: insight.snapshot.changedFiles,
                hasLineStats: insight.snapshot.hasDiffStats
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Kit941.Spacing.sm), count: 3), spacing: Kit941.Spacing.sm) {
                WorkMapMiniFact(label: "Span", value: activeSpanLabel)
                WorkMapMiniFact(label: "Type", value: insight.topCategory?.displayName ?? "None")
                WorkMapMiniFact(label: "Language", value: insight.topLanguage ?? "None")
            }

            if let topRepository = insight.topRepository {
                Label(shortRepositoryName(topRepository), systemImage: "shippingbox")
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(AppSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            if !insight.commitSample.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(insight.commitSample, id: \.id) { commit in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(commit.shortSHA)
                                .kit941Font(.caption, weight: .semibold)
                                .foregroundStyle(AppSurface.secondaryText)
                                .monospaced()
                            Text(commit.messageHeadline)
                                .kit941Font(.caption)
                                .foregroundStyle(AppSurface.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                }
            } else {
                Text("No imported work for this day.")
                    .kit941Font(.body)
                    .foregroundStyle(AppSurface.secondaryText)
            }
        }
        .padding(Kit941.Spacing.md)
        .appPanel()
    }

    private var primaryValue: String {
        switch metric {
        case .changes:
            guard insight.snapshot.hasDiffStats else {
                return insight.snapshot.commitCount.formatted()
            }
            return insight.snapshot.totalChanges.formatted()
        case .commits:
            return insight.snapshot.commitCount.formatted()
        }
    }

    private var primaryUnit: String {
        switch metric {
        case .changes:
            guard insight.snapshot.hasDiffStats else {
                return insight.snapshot.commitCount == 1 ? "commit awaiting line stats" : "commits awaiting line stats"
            }
            return insight.snapshot.isDiffStatsComplete ? "changed lines" : "known changed lines"
        case .commits:
            return insight.snapshot.commitCount == 1 ? "commit" : "commits"
        }
    }

    private var statusLabel: String {
        guard insight.snapshot.commitCount > 0 else {
            return "No work imported"
        }
        guard insight.snapshot.hasDiffStats else {
            return "Line stats pending"
        }
        return insight.snapshot.isDiffStatsComplete ? "Stats complete" : "\(insight.snapshot.coverage.formatted(.percent.precision(.fractionLength(0)))) stats coverage"
    }

    private var statusColor: Color {
        if insight.snapshot.commitCount == 0 {
            return AppSurface.secondaryText
        }
        return insight.snapshot.isDiffStatsComplete ? AppSurface.accent : AppSurface.warning
    }

    private var activeSpanLabel: String {
        guard let minutes = insight.activeSpanMinutes else {
            return insight.snapshot.commitCount > 0 ? "Single" : "None"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func shortRepositoryName(_ fullName: String) -> String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }
}

private struct WorkMapBalanceRail: View {
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let hasLineStats: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let width = max(proxy.size.width - spacing, 1)
                let additionWidth = segmentWidth(additions, totalWidth: width)
                HStack(spacing: spacing) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(additionColor)
                        .frame(width: additionWidth)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(deletionColor)
                        .frame(width: max(width - additionWidth, 0))
                }
            }
            .frame(height: 9)

            HStack(spacing: Kit941.Spacing.sm) {
                BalanceToken(text: hasLineStats ? "+\(additions.formatted())" : "+ pending", color: additionColor)
                BalanceToken(text: hasLineStats ? "-\(deletions.formatted())" : "- pending", color: deletionColor)
                Spacer(minLength: Kit941.Spacing.xs)
                DashboardFactPill(text: filesLabel)
            }
        }
        .opacity(hasLineStats ? 1 : 0.58)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var totalLines: Int {
        additions + deletions
    }

    private var additionColor: Color {
        hasLineStats ? AppSurface.accent : AppSurface.track.opacity(0.84)
    }

    private var deletionColor: Color {
        hasLineStats ? AppSurface.secondaryAccent : AppSurface.track.opacity(0.62)
    }

    private var filesLabel: String {
        guard hasLineStats else {
            return "files pending"
        }
        let unit = changedFiles == 1 ? "file" : "files"
        return "\(changedFiles.formatted()) \(unit)"
    }

    private var accessibilityLabel: String {
        guard hasLineStats else {
            return "Changed-line stats pending"
        }
        return "\(additions) additions, \(deletions) deletions, \(changedFiles) files"
    }

    private func segmentWidth(_ value: Int, totalWidth: CGFloat) -> CGFloat {
        guard hasLineStats, totalLines > 0 else {
            return totalWidth / 2
        }
        return totalWidth * CGFloat(value) / CGFloat(totalLines)
    }
}

private struct WorkMapMiniFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .kit941Font(.label, weight: .semibold)
                .foregroundStyle(AppSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
    }
}

private struct WorkMapRhythmPanel: View {
    let insights: WorkMapPeriodInsights
    let metric: WorkDisplayMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rhythm")
                        .kit941Font(.label, weight: .semibold)
                    Text(rangeDetail)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppSurface.accent)
                    .frame(width: 28, height: 28)
                    .background(AppSurface.accent.opacity(0.12), in: Circle())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(insights.activeDayCount.formatted())
                    .font(AppSurface.metricFont(size: 46))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(insights.activeDayCount == 1 ? "active day" : "active days")
                    .kit941Font(.title)
                    .foregroundStyle(AppSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Kit941.Spacing.sm), count: 3), spacing: Kit941.Spacing.sm) {
                WorkMapMiniFact(label: "Selected", value: streakLabel(insights.currentStreak))
                WorkMapMiniFact(label: "Longest", value: streakLabel(insights.longestStreak))
                WorkMapMiniFact(label: "Peak", value: peakWeekdayLabel)
            }

            if let busiestDay = insights.busiestDay {
                HStack(spacing: Kit941.Spacing.sm) {
                    Label(busiestDay.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), systemImage: "square.grid.3x3.fill")
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: Kit941.Spacing.sm)

                    DashboardFactPill(text: "\(metric.value(for: busiestDay).formatted()) \(metric.shortUnit)")
                }
            }
        }
        .padding(Kit941.Spacing.md)
        .appPanel()
    }

    private var rangeDetail: String {
        guard let first = insights.firstActiveDate, let last = insights.lastActiveDate else {
            return "No active days in this range."
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return "Work appears on \(first.formatted(.dateTime.month(.abbreviated).day()))."
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) through \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var peakWeekdayLabel: String {
        insights.mostActiveWeekday.map(weekdayName) ?? "None"
    }

    private func streakLabel(_ days: Int) -> String {
        days == 1 ? "1d" : "\(days.formatted())d"
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else {
            return "Day"
        }
        return symbols[weekday - 1]
    }
}

private struct DataCoverageBar: View {
    let summary: WorkRangeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppSurface.track)
                    Capsule()
                        .fill(summary.isDiffStatsComplete ? AppSurface.accent : AppSurface.warning)
                        .frame(width: max(4, proxy.size.width * CGFloat(min(max(summary.coverage, 0), 1))))
                }
            }
            .frame(height: 7)

            HStack(spacing: Kit941.Spacing.sm) {
                Text(coverageLabel)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
                Text(summary.coverage.formatted(.percent.precision(.fractionLength(0))))
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(summary.isDiffStatsComplete ? AppSurface.accent : AppSurface.warning)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(coverageLabel)
    }

    private var coverageLabel: String {
        if summary.isDiffStatsComplete {
            return "Complete changes data"
        }
        let backed = summary.statsBackedCommitCount.formatted()
        let total = summary.commitCount.formatted()
        return "\(backed) of \(total) commits have changed-line data"
    }
}

private struct ComparisonMarkView: View {
    let currentAverage: Double
    let baselineAverage: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = proxy.size.height
                let maxValue = max(currentAverage, baselineAverage, 1)
                let baselineX = clampedX(for: baselineAverage, maxValue: maxValue, width: width)
                let currentX = clampedX(for: currentAverage, maxValue: maxValue, width: width)
                let centerY = height / 2

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppSurface.track.opacity(0.94))
                        .frame(height: 2)
                        .position(x: width / 2, y: centerY)

                    Capsule()
                        .fill(AppSurface.tertiaryText.opacity(0.46))
                        .frame(width: max(2, baselineX), height: 2)
                        .position(x: max(1, baselineX / 2), y: centerY)

                    Capsule()
                        .fill(AppSurface.accent)
                        .frame(width: max(2, currentX), height: 5)
                        .position(x: max(1, currentX / 2), y: centerY)

                    Rectangle()
                        .fill(AppSurface.secondaryText.opacity(0.72))
                        .frame(width: 2, height: 16)
                        .position(x: baselineX, y: centerY)

                    Circle()
                        .fill(AppSurface.accent)
                        .frame(width: 9, height: 9)
                        .position(x: currentX, y: centerY)
                }
            }

            HStack {
                Label("Current \(formatted(currentAverage)) \(unit)/day", systemImage: "circle.fill")
                    .foregroundStyle(AppSurface.accent)
                Spacer(minLength: Kit941.Spacing.sm)
                Label("Prior \(formatted(baselineAverage)) \(unit)/day", systemImage: "minus")
                    .foregroundStyle(AppSurface.secondaryText)
            }
            .kit941Font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .accessibilityLabel("Current average \(formatted(currentAverage)) \(unit) per day, prior \(formatted(baselineAverage)) \(unit) per day")
    }

    private func clampedX(for value: Double, maxValue: Double, width: CGFloat) -> CGFloat {
        guard maxValue > 0 else {
            return 0
        }
        let x = width * CGFloat(max(0, min(value / maxValue, 1)))
        return min(max(x, 4), max(width - 4, 4))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct PeriodBarTrendView: View {
    let summaries: [WorkRangeSummary]
    let scope: WorkRangeScope
    let metric: WorkDisplayMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                        let value = barValue(for: summary)
                        let height = barHeight(value, availableHeight: proxy.size.height)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(for: summary, index: index))
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                            .accessibilityLabel(accessibilityLabel(for: summary, index: index))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            HStack {
                Text(currentLabel)
                Spacer(minLength: Kit941.Spacing.sm)
                Text(peakLabel)
            }
            .kit941Font(.caption)
            .foregroundStyle(AppSurface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
    }

    private var currentIndex: Int {
        max(summaries.count - 1, 0)
    }

    private var values: [Int] {
        summaries.map(barValue(for:))
    }

    private var maxValue: Int {
        max(values.max() ?? 0, 1)
    }

    private var currentSummary: WorkRangeSummary? {
        summaries.last
    }

    private var currentLabel: String {
        guard let currentSummary else {
            return "No periods"
        }
        return "Selected \(barValue(for: currentSummary).formatted()) \(metric.shortUnit)"
    }

    private var peakLabel: String {
        "Peak \(maxValue.formatted()) \(metric.shortUnit)"
    }

    private func barValue(for summary: WorkRangeSummary) -> Int {
        switch metric {
        case .changes:
            return summary.statsBackedCommitCount > 0 ? summary.totalChanges : 0
        case .commits:
            return summary.commitCount
        }
    }

    private func barHeight(_ value: Int, availableHeight: CGFloat) -> CGFloat {
        guard value > 0 else {
            return 5
        }
        let ratio = CGFloat(value) / CGFloat(maxValue)
        return max(12, min(availableHeight, ratio * availableHeight))
    }

    private func barColor(for summary: WorkRangeSummary, index: Int) -> Color {
        if metric == .changes && summary.statsBackedCommitCount == 0 && summary.commitCount > 0 {
            return AppSurface.warning.opacity(0.35)
        }
        if index == currentIndex {
            return AppSurface.accent
        }
        if metric == .changes && !summary.isDiffStatsComplete {
            return AppSurface.accent.opacity(0.45)
        }
        return AppSurface.track.opacity(0.95)
    }

    private func accessibilityLabel(for summary: WorkRangeSummary, index: Int) -> String {
        let prefix = index == currentIndex ? "Selected \(scope.lowerTitle)" : scope.title
        let value = barValue(for: summary).formatted()
        if metric == .changes && summary.statsBackedCommitCount == 0 && summary.commitCount > 0 {
            return "\(prefix), changed-line stats pending"
        }
        return "\(prefix), \(value) \(metric.shortUnit)"
    }
}

private struct WorkBreakdownStrip: View {
    let summary: WorkRangeSummary
    let dimension: WorkBreakdownDimension

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if items.isEmpty {
                Text(emptyMessage)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(items, id: \.name) { item in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(item.color)
                                .frame(width: segmentWidth(item.value, totalWidth: proxy.size.width))
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 10) {
                    ForEach(Array(items.prefix(3)), id: \.name) { item in
                        Label {
                            Text("\(item.name) \(percentLabel(item.value))")
                        } icon: {
                            Image(systemName: item.symbolName)
                        }
                        .foregroundStyle(item.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    }
                }
                .kit941Font(.caption, weight: .semibold)
            }
        }
    }

    private var items: [BreakdownItem] {
        switch dimension {
        case .type:
            return WorkCategory.allCases
                .compactMap { category in
                    let value = summary.categoryWeights[category] ?? 0
                    guard value > 0 else { return nil }
                    return BreakdownItem(
                        name: category.displayName,
                        value: value,
                        color: category.workMixColor,
                        symbolName: category.workMixSymbol
                    )
                }
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0 }
        case .language:
            return summary.languageWeights
                .map { language, value in
                    BreakdownItem(
                        name: language,
                        value: value,
                        color: languageColor(language),
                        symbolName: "doc.text"
                    )
                }
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0 }
        }
    }

    private var totalValue: Int {
        max(items.reduce(0) { $0 + $1.value }, 1)
    }

    private var emptyMessage: String {
        switch dimension {
        case .type: "No type breakdown for this range."
        case .language: "Language appears after diff stats sync."
        }
    }

    private func segmentWidth(_ value: Int, totalWidth: CGFloat) -> CGFloat {
        max(6, totalWidth * CGFloat(value) / CGFloat(totalValue))
    }

    private func percentLabel(_ value: Int) -> String {
        (Double(value) / Double(totalValue)).formatted(.percent.precision(.fractionLength(0)))
    }

    private func languageColor(_ language: String) -> Color {
        AppSurface.languageColor(language)
    }

    private struct BreakdownItem {
        let name: String
        let value: Int
        let color: Color
        let symbolName: String
    }
}

private struct SelectedDayAnnotationRow: View {
    let selectedDate: Date
    let snapshot: DayWorkSnapshot
    let metric: WorkDisplayMetric
    let summary: DailyJournalSummaryRecord?
    let onShowDayDetail: @MainActor @Sendable () -> Void

    var body: some View {
        Button {
            onShowDayDetail()
        } label: {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                    Text(metricSummary)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: Kit941.Spacing.sm)

                Text(statusLabel)
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppSurface.secondaryText)
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.sm)
            .appPanel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open selected day detail")
    }

    private var metricSummary: String {
        guard snapshot.commitCount > 0 else {
            return "No imported work"
        }
        switch metric {
        case .commits:
            let unit = snapshot.commitCount == 1 ? "commit" : "commits"
            if snapshot.statsBackedCommitCount > 0 {
                return "\(snapshot.commitCount.formatted()) \(unit), \(snapshot.totalChanges.formatted()) known lines"
            }
            return "\(snapshot.commitCount.formatted()) \(unit)"
        case .changes:
            if snapshot.mode == .diffBacked {
                return "\(snapshot.displayValue.formatted()) \(snapshot.displayUnit), \(snapshot.changedFiles.formatted()) files"
            }
            if snapshot.statsBackedCommitCount > 0 {
                return "\(snapshot.displayValue.formatted()) \(snapshot.displayUnit), +\(snapshot.additions.formatted()) -\(snapshot.deletions.formatted())"
            }
            let coverage = snapshot.coverage.formatted(.percent.precision(.fractionLength(0)))
            return "\(snapshot.commitCount.formatted()) commits, \(coverage) stats coverage"
        }
    }

    private var statusLabel: String {
        if summary != nil {
            return "Journal"
        }
        return snapshot.commitCount > 0 ? "Open" : "Empty"
    }

    private var statusColor: Color {
        summary == nil ? AppSurface.secondaryText : AppSurface.accent
    }
}

private extension WorkCategory {
    var workMixSymbol: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .tests: "checkmark.seal"
        case .docs: "doc.text"
        case .design: "paintpalette"
        case .infra: "server.rack"
        case .release: "shippingbox"
        case .unknown: "questionmark.circle"
        }
    }

    var workMixColor: Color {
        AppSurface.categoryColor(self)
    }
}
