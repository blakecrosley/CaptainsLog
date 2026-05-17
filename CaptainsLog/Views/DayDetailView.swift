import SwiftUI
import Kit941

private enum DayDetailMode: String, CaseIterable, Identifiable {
    case journal
    case commits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: "Journal"
        case .commits: "Commits"
        }
    }
}

struct DayDetailView: View {
    let selectedDate: Date
    let commits: [GitCommitRecord]
    let workSnapshot: DayWorkSnapshot
    let summary: DailyJournalSummaryRecord?
    let isGeneratingSummary: Bool
    let generationError: String?
    let generationProvider: JournalSummaryProvider?

    @State private var selectedMode: DayDetailMode = .journal

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .kit941Font(.title, weight: .bold)
                    Text(metricSummary)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Picker("Day view", selection: $selectedMode) {
                    ForEach(DayDetailMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let generationError {
                Label(generationError, systemImage: "exclamationmark.triangle")
                    .kit941Font(.label)
                    .foregroundStyle(AppSurface.danger)
            }

            switch selectedMode {
            case .journal:
                journalContent
            case .commits:
                CommitListView(commits: commits)
            }
        }
    }

    @ViewBuilder
    private var journalContent: some View {
        if isGeneratingSummary {
            Kit941.Card {
                HStack(spacing: Kit941.Spacing.md) {
                    ProgressView()
                    Text("Generating journal entry")
                        .kit941Font(.body)
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }
        } else if let summary {
            SummaryView(summary: summary)
        } else if commits.isEmpty {
            Kit941.StatusView(
                style: .empty,
                symbol: "calendar.badge.clock",
                headline: "No commits imported",
                description: "Choose another day or sync repositories from GitHub."
            )
        } else {
            Kit941.StatusView(
                style: .empty,
                symbol: generationProvider?.symbolName ?? "sparkles",
                headline: "No journal yet",
                description: "Generate a summary from this day's commits."
            )
        }
    }

    private var metricSummary: String {
        if workSnapshot.statsBackedCommitCount > 0 {
            return "\(workSnapshot.displayValue.formatted()) \(workSnapshot.displayUnit), +\(workSnapshot.additions.formatted()) -\(workSnapshot.deletions.formatted()), \(workSnapshot.changedFiles.formatted()) files"
        }
        let coverage = workSnapshot.coverage.formatted(.percent.precision(.fractionLength(0)))
        return "\(commits.count.formatted()) commits, \(coverage) stats coverage"
    }
}

private struct SummaryView: View {
    let summary: DailyJournalSummaryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Kit941.Spacing.sm) {
                    Text(summary.title)
                        .kit941Font(.title, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if summary.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppSurface.secondaryText)
                            .accessibilityLabel("Locked")
                    }
                }

                Text(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
            }

            Text(summary.narrative)
                .kit941Font(.body)
                .foregroundStyle(AppSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Kit941.Spacing.xs)

            if !summary.bullets.isEmpty {
                VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                    ForEach(Array(summary.bullets.enumerated()), id: \.offset) { index, bullet in
                        JournalBulletRow(index: index + 1, text: bullet)
                    }
                }
            }

            if !summary.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(summary.tags, id: \.self) { tag in
                        Text(tag)
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppSurface.mutedFill(opacity: 0.92), in: Capsule())
                    }
                }
            }

            HStack(spacing: Kit941.Spacing.sm) {
                SummarySourcePill(
                    symbol: "number",
                    text: "\(summary.sourceCommitIDs.count.formatted()) source commits"
                )
                SummarySourcePill(
                    symbol: "sparkles",
                    text: summary.modelName
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Kit941.Spacing.lg)
        .appPanel(highlighted: true)
    }
}

private struct JournalBulletRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Kit941.Spacing.sm) {
            Text(index.formatted())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppSurface.accent)
                .frame(width: 24, height: 24)
                .background(AppSurface.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .kit941Font(.body)
                .foregroundStyle(AppSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SummarySourcePill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .kit941Font(.caption)
            .foregroundStyle(AppSurface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppSurface.mutedFill(opacity: 0.84), in: Capsule())
    }
}

private struct CommitListView: View {
    let commits: [GitCommitRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text("Commits")
                .kit941Font(.title, weight: .semibold)

            if commits.isEmpty {
                Text("Nothing imported for this day.")
                    .kit941Font(.body)
                    .foregroundStyle(AppSurface.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(commits) { commit in
                        NavigationLink {
                            CommitEvidenceView(commit: commit)
                        } label: {
                            CommitRow(commit: commit)
                        }
                        .buttonStyle(.plain)
                        if commit.id != commits.last?.id {
                            Divider()
                        }
                    }
                }
                .appPanel()
            }
        }
    }
}

private struct CommitRow: View {
    let commit: GitCommitRecord

    var body: some View {
        HStack(alignment: .top, spacing: Kit941.Spacing.md) {
            VStack(spacing: 4) {
                Circle()
                    .fill(AppSurface.accent)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(AppSurface.divider.opacity(0.82))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(commit.messageHeadline)
                    .kit941Font(.body, weight: .semibold)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(commit.repositoryFullName)
                    Text(commit.shortSHA)
                    Text(commit.authoredAt, style: .time)
                }
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)

                Text(statsLabel)
                    .kit941Font(.caption)
                    .foregroundStyle(statsColor)

                if !commit.messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(commit.messageBody)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppSurface.secondaryText)
        }
        .padding(Kit941.Spacing.md)
        .contentShape(Rectangle())
    }

    private var statsLabel: String {
        if commit.hasDiffStats {
            return "+\((commit.additions ?? 0).formatted()) -\((commit.deletions ?? 0).formatted()) / \((commit.changedFileCount ?? 0).formatted()) files"
        }
        if commit.diffStatsError != nil {
            return "Diff stats skipped"
        }
        return "Diff stats pending"
    }

    private var statsColor: Color {
        commit.hasDiffStats ? AppSurface.accent : AppSurface.secondaryText
    }
}

struct CommitEvidenceView: View {
    @Environment(\.openURL) private var openURL

    let commit: GitCommitRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                headerCard
                statsCard
                filesCard
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppSurface.backgroundGradient.ignoresSafeArea())
        .navigationTitle(commit.shortSHA)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var headerCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text(commit.messageHeadline)
                    .kit941Font(.title, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)

                if !commit.messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(commit.messageBody)
                        .kit941Font(.body)
                        .foregroundStyle(AppSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 7) {
                    evidenceRow("Repository", value: commit.repositoryFullName)
                    evidenceRow("Commit", value: commit.sha)
                    evidenceRow("Author", value: commit.authorLogin ?? "Unlinked Git author")
                    evidenceRow("Authored", value: commit.authoredAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let url = commit.htmlURL {
                    Kit941.Button(role: .secondary) {
                        await MainActor.run { openURL(url) }
                    } label: {
                        Label("Open on GitHub", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var statsCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text("Changes")
                    .kit941Font(.title, weight: .semibold)

                if commit.hasDiffStats {
                    HStack(spacing: Kit941.Spacing.md) {
                        evidenceMetric("+\((commit.additions ?? 0).formatted())", label: "Additions", color: AppSurface.accent)
                        evidenceMetric("-\((commit.deletions ?? 0).formatted())", label: "Deletions", color: AppSurface.warning)
                        evidenceMetric("\((commit.changedFileCount ?? 0).formatted())", label: "Files", color: AppSurface.secondaryText)
                    }
                } else {
                    Label(diffStatusLabel, systemImage: "clock")
                        .kit941Font(.body)
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var filesCard: some View {
        let files = commit.changedFiles
        if !files.isEmpty {
            Kit941.Card {
                VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                    Text("Changed Files")
                        .kit941Font(.title, weight: .semibold)

                    VStack(spacing: 0) {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: Kit941.Spacing.sm) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(AppSurface.secondaryText)
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(AppSurface.primaryText)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)

                            if file != files.last {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func evidenceRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Kit941.Spacing.sm) {
            Text(title)
                .kit941Font(.caption, weight: .semibold)
                .foregroundStyle(AppSurface.secondaryText)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.primaryText)
                .textSelection(.enabled)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }

    private func evidenceMetric(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .kit941Font(.title, weight: .bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .kit941Font(.caption)
                .foregroundStyle(AppSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diffStatusLabel: String {
        if commit.diffStatsError != nil {
            return "Line stats skipped"
        }
        return "Line stats pending"
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = rows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if current.width + size.width + (current.indices.isEmpty ? 0 : spacing) > maxWidth,
               !current.indices.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.indices.append(index)
            current.width += size.width + (current.indices.count == 1 ? 0 : spacing)
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct FlowRow {
        var indices: [Subviews.Index] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}
