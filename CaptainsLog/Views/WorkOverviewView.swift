import SwiftUI
import Kit941

struct WorkOverviewView: View {
    @Binding var selectedDate: Date

    let workMetrics: WorkMetrics
    let selectedWorkSnapshot: DayWorkSnapshot
    let selectedSummary: DailyJournalSummaryRecord?
    let repositories: [GitRepositoryRecord]
    let githubLogin: String?
    let githubAvatarURL: URL?
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let updatedDiffStatCount: Int
    let lastSyncedAt: Date?
    let hasOpenAIKey: Bool
    let onShowAccounts: @MainActor @Sendable () -> Void
    let onRefreshToday: @MainActor @Sendable () -> Void
    let onShowSettings: @MainActor @Sendable () -> Void
    let onShowAISettings: @MainActor @Sendable () -> Void
    let onShowMonth: @MainActor @Sendable () -> Void
    let onShowDayDetail: @MainActor @Sendable () -> Void

    @State private var displayMetric: WorkDisplayMetric = .changes

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.xl) {
            overviewHeader
            JournalWeekStrip(
                selectedDate: $selectedDate,
                workMetrics: workMetrics,
                onShowMonth: onShowMonth
            )
            PeriodReadView(
                trend: trend,
                summary: rangeSummary,
                trendSummaries: trendLineSummaries,
                metric: $displayMetric
            )
            ActivityHeatmapView(
                selectedDate: $selectedDate,
                workMetrics: workMetrics,
                metric: displayMetric
            )
            SelectedDayAnnotationRow(
                selectedDate: selectedDate,
                snapshot: selectedWorkSnapshot,
                summary: selectedSummary,
                onShowDayDetail: onShowDayDetail
            )
        }
    }

    private var trend: WorkTrendSummary {
        workMetrics.trend(scope: .week, containing: selectedDate)
    }

    private var rangeSummary: WorkRangeSummary {
        workMetrics.rangeSummary(scope: .week, containing: selectedDate)
    }

    private var trendLineSummaries: [WorkRangeSummary] {
        let calendar = Calendar.current
        return (0..<10).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: selectedDate) else {
                return nil
            }
            return workMetrics.rangeSummary(scope: .week, containing: date)
        }
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
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 38, height: 38)
                    } else {
                        iconButton("Refresh Today", systemImage: "arrow.clockwise", action: onRefreshToday)
                    }
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
                updatedDiffStatCount: updatedDiffStatCount,
                lastSyncedAt: lastSyncedAt
            )
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
    let lastSyncedAt: Date?

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
        if let lastSyncedAt {
            return "Last sync \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(selectedRepositoryCount.formatted()) of \(repositoryCount.formatted()) repositories selected"
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

private struct PeriodReadView: View {
    let trend: WorkTrendSummary
    let summary: WorkRangeSummary
    let trendSummaries: [WorkRangeSummary]
    @Binding var metric: WorkDisplayMetric

    @State private var breakdownDimension: WorkBreakdownDimension = .type

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected week")
                        .kit941Font(.label, weight: .semibold)
                    Text(dateRangeLabel)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    Label(comparisonLabel, systemImage: metricDirection.symbolName)
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(directionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(dataBasisLabel)
                        .kit941Font(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Picker("Metric", selection: $metric) {
                ForEach(WorkDisplayMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.value(for: summary).formatted())
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Text(metric.unit(for: summary))
                    .kit941Font(.body)
                    .foregroundStyle(.secondary)
            }

            if summary.statsBackedCommitCount > 0 {
                Text(changeCompositionLabel)
                    .kit941Font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            WorkTrendLineView(
                summaries: trendSummaries,
                metric: metric
            )
            .frame(height: 96)

            if summary.commitCount > 0 {
                if canShowComparisonMark {
                    ComparisonMarkView(
                        currentAverage: metric.averagePerDay(for: summary),
                        baselineAverage: metric.averagePerDay(for: trend.baseline),
                        unit: metric.shortUnit
                    )
                    .frame(height: 42)
                }

                Picker("Breakdown", selection: $breakdownDimension) {
                    ForEach(WorkBreakdownDimension.allCases) { dimension in
                        Text(dimension.title).tag(dimension)
                    }
                }
                .pickerStyle(.segmented)

                WorkBreakdownStrip(summary: summary, dimension: breakdownDimension)
            } else {
                Text("No imported work in this week.")
                    .kit941Font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Kit941.Spacing.md) {
                stat("Commits", value: summary.commitCount.formatted())
                stat("Changed files", value: summary.changedFiles.formatted())
                stat("Stats coverage", value: summary.coverage.formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .padding(Kit941.Spacing.md)
        .background(.background, in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var dateRangeLabel: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: summary.end) ?? summary.end
        if calendar.isDate(summary.start, inSameDayAs: end) {
            return summary.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return "\(summary.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var comparisonLabel: String {
        guard let percentChange = metricPercentChange else {
            return "Building baseline"
        }
        let formatted = percentChange.formatted(.percent.precision(.fractionLength(0)))
        let signed = percentChange > 0 ? "+\(formatted)" : formatted
        return "\(signed) vs prior week"
    }

    private var dataBasisLabel: String {
        guard summary.commitCount > 0 else {
            return "No imported work"
        }
        if metric == .commits {
            return "GitHub commits from selected repositories"
        }
        guard summary.statsBackedCommitCount > 0 else {
            return "Waiting for diff stats"
        }
        let backed = summary.statsBackedCommitCount.formatted()
        let total = summary.commitCount.formatted()
        return switch summary.mode {
        case .diffBacked: "Diff stats on \(backed) of \(total) commits"
        case .commitEstimate: "Partial diff stats: \(backed) of \(total)"
        }
    }

    private var changeCompositionLabel: String {
        "+\(summary.additions.formatted()) -\(summary.deletions.formatted()) across \(summary.changedFiles.formatted()) files"
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
                        .fill(Color.primary.opacity(0.09))
                        .frame(height: 2)
                        .position(x: width / 2, y: centerY)

                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: max(2, baselineX), height: 2)
                        .position(x: max(1, baselineX / 2), y: centerY)

                    Capsule()
                        .fill(AppSurface.accent)
                        .frame(width: max(2, currentX), height: 5)
                        .position(x: max(1, currentX / 2), y: centerY)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
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
                    .foregroundStyle(.secondary)
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

private struct WorkTrendLineView: View {
    let summaries: [WorkRangeSummary]
    let metric: WorkDisplayMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let values = summaries.map { metric.value(for: $0) }
                let points = trendPoints(values: values, size: proxy.size)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.055))
                        .frame(height: 1)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 1)

                    Path { path in
                        guard let first = points.first else {
                            return
                        }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(AppSurface.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(index == points.count - 1 ? AppSurface.accent : Color.primary.opacity(0.28))
                            .frame(width: index == points.count - 1 ? 7 : 4, height: index == points.count - 1 ? 7 : 4)
                            .position(point)
                    }
                }
            }

            HStack {
                Text("Last \(summaries.count) weeks")
                Spacer(minLength: Kit941.Spacing.sm)
                Text(peakLabel)
            }
            .kit941Font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var peakLabel: String {
        let peak = summaries.map { metric.value(for: $0) }.max() ?? 0
        return "Peak \(peak.formatted()) \(metric.shortUnit)"
    }

    private var accessibilityLabel: String {
        let values = summaries.map { metric.value(for: $0).formatted() }.joined(separator: ", ")
        return "Recent weekly \(metric.title.lowercased()) trend: \(values)"
    }

    private func trendPoints(values: [Int], size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else {
            return []
        }

        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let maxValue = max(values.max() ?? 0, 1)
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            let x = values.count > 1 ? CGFloat(index) * step : width / 2
            let ratio = CGFloat(value) / CGFloat(maxValue)
            let y = height - max(4, ratio * (height - 8))
            return CGPoint(x: x, y: min(max(y, 4), height - 4))
        }
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
                    .foregroundStyle(.secondary)
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
        switch language {
        case "Swift": AppSurface.accent
        case "TypeScript": Color(red: 0.18, green: 0.39, blue: 0.78)
        case "JavaScript": Color(red: 0.70, green: 0.53, blue: 0.10)
        case "Python": Color(red: 0.25, green: 0.43, blue: 0.64)
        case "CSS": Color(red: 0.48, green: 0.31, blue: 0.78)
        case "HTML": Color(red: 0.78, green: 0.34, blue: 0.18)
        case "Docs": Color(red: 0.62, green: 0.38, blue: 0.12)
        case "Assets": Color(red: 0.72, green: 0.25, blue: 0.43)
        case "JSON", "YAML", "Property List": Color(red: 0.38, green: 0.38, blue: 0.44)
        default: Color.secondary
        }
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
                        .foregroundStyle(.primary)
                    Text(metricSummary)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.sm)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open selected day detail")
    }

    private var metricSummary: String {
        guard snapshot.commitCount > 0 else {
            return "No imported work"
        }
        if snapshot.mode == .diffBacked {
            return "\(snapshot.displayValue.formatted()) \(snapshot.displayUnit), \(snapshot.changedFiles.formatted()) files"
        }
        if snapshot.statsBackedCommitCount > 0 {
            return "\(snapshot.displayValue.formatted()) \(snapshot.displayUnit), +\(snapshot.additions.formatted()) -\(snapshot.deletions.formatted())"
        }
        let coverage = snapshot.coverage.formatted(.percent.precision(.fractionLength(0)))
        return "\(snapshot.commitCount.formatted()) commits, \(coverage) stats coverage"
    }

    private var statusLabel: String {
        if summary != nil {
            return "Journal"
        }
        return snapshot.commitCount > 0 ? "Open" : "Empty"
    }

    private var statusColor: Color {
        summary == nil ? .secondary : AppSurface.accent
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
        switch self {
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
