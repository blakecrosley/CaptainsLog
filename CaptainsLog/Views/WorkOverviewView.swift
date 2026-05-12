import SwiftUI
import Kit941

struct WorkOverviewView: View {
    @Binding var selectedDate: Date
    @Binding var scope: WorkRangeScope

    let workMetrics: WorkMetrics
    let activityMetrics: ActivityMetrics
    let repositories: [GitRepositoryRecord]
    let githubLogin: String?
    let githubAvatarURL: URL?
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let updatedDiffStatCount: Int
    let hasOpenAIKey: Bool
    let onShowAccounts: @MainActor @Sendable () -> Void
    let onShowSettings: @MainActor @Sendable () -> Void
    let onShowAISettings: @MainActor @Sendable () -> Void
    let onShowMonth: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            overviewHeader
            JournalWeekStrip(
                selectedDate: $selectedDate,
                metrics: activityMetrics,
                onShowMonth: onShowMonth
            )
            selectedDateStrip
            rangePicker
            WorkTrendCard(trend: trend)
            WorkMixCard(summary: rangeSummary)
            ActivityHeatmapView(
                selectedDate: $selectedDate,
                metrics: activityMetrics
            )
        }
    }

    private var trend: WorkTrendSummary {
        workMetrics.trend(scope: scope, containing: selectedDate)
    }

    private var rangeSummary: WorkRangeSummary {
        workMetrics.rangeSummary(scope: scope, containing: selectedDate)
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
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch GitHub account")

                Spacer(minLength: Kit941.Spacing.sm)

                HStack(spacing: Kit941.Spacing.xs) {
                    iconButton("AI", systemImage: hasOpenAIKey ? "sparkles" : "sparkles.slash", action: onShowAISettings)
                    iconButton("Settings", systemImage: "gearshape", action: onShowSettings)
                }
            }

            SyncStatusStrip(
                repositoryCount: repositories.count,
                selectedRepositoryCount: repositories.filter(\.isSelected).count,
                isSyncing: isSyncing,
                syncMessage: syncMessage,
                importedCommitCount: importedCommitCount,
                updatedDiffStatCount: updatedDiffStatCount
            )
        }
    }

    private var accountTitle: String {
        if let githubLogin {
            return githubLogin
        }
        return "GitHub"
    }

    private var rangePicker: some View {
        Picker("Range", selection: $scope) {
            ForEach(WorkRangeScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Work range")
    }

    private var selectedDateStrip: some View {
        HStack(spacing: Kit941.Spacing.sm) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppSurface.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Selected date")
                    .kit941Font(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                    .kit941Font(.label, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Text(scope.title)
                .kit941Font(.caption, weight: .semibold)
                .foregroundStyle(AppSurface.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppSurface.accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, Kit941.Spacing.md)
        .padding(.vertical, Kit941.Spacing.sm)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct SyncStatusStrip: View {
    let repositoryCount: Int
    let selectedRepositoryCount: Int
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let updatedDiffStatCount: Int

    var body: some View {
        HStack(spacing: Kit941.Spacing.sm) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .kit941Font(.label, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(detail)
                    .kit941Font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Kit941.Spacing.md)
        .padding(.vertical, Kit941.Spacing.sm)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
    }

    private var statusIcon: some View {
        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppSurface.accent)
    }

    private var title: String {
        if isSyncing {
            return "Syncing GitHub"
        }
        return repositoryCount > 0 ? "GitHub history" : "GitHub connected"
    }

    private var detail: String {
        if !syncMessage.isEmpty {
            return syncMessage
        }
        if importedCommitCount > 0 || updatedDiffStatCount > 0 {
            return "\(importedCommitCount.formatted()) commits, \(updatedDiffStatCount.formatted()) diff stats this run"
        }
        return "\(selectedRepositoryCount.formatted()) of \(repositoryCount.formatted()) repositories selected"
    }
}

private struct WorkTrendCard: View {
    let trend: WorkTrendSummary

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Work Done")
                            .kit941Font(.title, weight: .semibold)
                        Text(trend.current.mode.label)
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Label(trend.direction.label, systemImage: trend.direction.symbolName)
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(directionColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(directionColor.opacity(0.12), in: Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trend.current.displayValue.formatted())
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    Text(trend.current.displayUnit)
                        .kit941Font(.body)
                        .foregroundStyle(.secondary)
                }

                TrendLineView(currentAverage: trend.current.averagePerDay, baselineAverage: trend.baseline.averagePerDay)
                    .frame(height: 42)

                HStack(spacing: Kit941.Spacing.md) {
                    stat("Avg/day", value: trend.current.averagePerDay.formatted(.number.precision(.fractionLength(1))))
                    stat("Baseline", value: trend.baseline.averagePerDay.formatted(.number.precision(.fractionLength(1))))
                    stat("Coverage", value: trend.current.coverage.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
    }

    private var directionColor: Color {
        switch trend.direction {
        case .up: AppSurface.accent
        case .steady: .secondary
        case .down: Kit941.Status.warning
        case .noBaseline: .secondary
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .kit941Font(.label, weight: .semibold)
                .monospacedDigit()
            Text(label)
                .kit941Font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrendLineView: View {
    let currentAverage: Double
    let baselineAverage: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let maxValue = max(currentAverage, baselineAverage, 1)
            let baselineY = y(for: baselineAverage, maxValue: maxValue, height: height)
            let currentY = y(for: currentAverage, maxValue: maxValue, height: height)

            ZStack(alignment: .leading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baselineY))
                    path.addLine(to: CGPoint(x: width, y: baselineY))
                }
                .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: baselineY))
                    path.addCurve(
                        to: CGPoint(x: width, y: currentY),
                        control1: CGPoint(x: width * 0.35, y: baselineY),
                        control2: CGPoint(x: width * 0.65, y: currentY)
                    )
                }
                .stroke(AppSurface.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                Circle()
                    .fill(AppSurface.accent)
                    .frame(width: 9, height: 9)
                    .position(x: width, y: currentY)
            }
        }
        .accessibilityHidden(true)
    }

    private func y(for value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let normalized = max(0, min(value / maxValue, 1))
        return height - (height * 0.78 * normalized) - 4
    }
}

private struct WorkMixCard: View {
    let summary: WorkRangeSummary

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Work Mix")
                            .kit941Font(.title, weight: .semibold)
                        Text("\(summary.commitCount.formatted()) commits across selected repositories")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if topCategories.isEmpty {
                    Text("No work imported for this range.")
                        .kit941Font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Kit941.Spacing.sm) {
                        ForEach(topCategories, id: \.category) { item in
                            WorkMixRow(category: item.category, value: item.value, maxValue: maxCategoryValue)
                        }
                    }
                }

                if !topRepositories.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                        Text("Repo Focus")
                            .kit941Font(.label, weight: .semibold)
                        ForEach(topRepositories, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                    .kit941Font(.caption, weight: .semibold)
                                    .lineLimit(1)
                                Spacer(minLength: Kit941.Spacing.sm)
                                Text(item.value.formatted())
                                    .kit941Font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    private var topCategories: [(category: WorkCategory, value: Int)] {
        WorkCategory.allCases
            .compactMap { category in
                let value = summary.categoryWeights[category] ?? 0
                return value > 0 ? (category, value) : nil
            }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }

    private var maxCategoryValue: Int {
        max(topCategories.map(\.value).max() ?? 1, 1)
    }

    private var topRepositories: [(name: String, value: Int)] {
        summary.repositoryWeights
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0 }
    }
}

private struct WorkMixRow: View {
    let category: WorkCategory
    let value: Int
    let maxValue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(category.displayName, systemImage: symbol)
                    .kit941Font(.caption, weight: .semibold)
                Spacer(minLength: Kit941.Spacing.sm)
                Text(value.formatted())
                    .kit941Font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(color)
                        .frame(width: max(8, proxy.size.width * CGFloat(value) / CGFloat(maxValue)))
                }
            }
            .frame(height: 7)
        }
    }

    private var symbol: String {
        switch category {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .tests: "checkmark.seal"
        case .docs: "doc.text"
        case .design: "paintpalette"
        case .infra: "server.rack"
        case .release: "shippingbox"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch category {
        case .code: AppSurface.accent
        case .tests: Color(red: 0.18, green: 0.45, blue: 0.90)
        case .docs: Color(red: 0.62, green: 0.38, blue: 0.12)
        case .design: Color(red: 0.72, green: 0.25, blue: 0.43)
        case .infra: Color(red: 0.38, green: 0.38, blue: 0.44)
        case .release: Color(red: 0.52, green: 0.42, blue: 0.82)
        case .unknown: Color.secondary
        }
    }
}
