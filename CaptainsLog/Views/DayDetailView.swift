import SwiftUI
import Kit941

struct DayDetailView: View {
    let selectedDate: Date
    let commits: [GitCommitRecord]
    let workSnapshot: DayWorkSnapshot
    let summary: DailyJournalSummaryRecord?
    let isGeneratingSummary: Bool
    let generationError: String?
    let canGenerate: Bool
    let generationProvider: JournalSummaryProvider?
    let onGenerate: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .kit941Font(.title, weight: .bold)
                    Text(metricSummary)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Kit941.Spacing.md)

                Kit941.Button(role: .secondary) {
                    await MainActor.run { onGenerate() }
                } label: {
                    Label(summary == nil ? "Generate" : "Regenerate", systemImage: generationProvider?.symbolName ?? "sparkles")
                }
                .disabled(!canGenerate || isGeneratingSummary)
            }

            if let generationError {
                Label(generationError, systemImage: "exclamationmark.triangle")
                    .kit941Font(.label)
                    .foregroundStyle(Kit941.Status.danger)
            }

            if isGeneratingSummary {
                Kit941.Card {
                    HStack(spacing: Kit941.Spacing.md) {
                        ProgressView()
                        Text("Generating journal entry")
                            .kit941Font(.body)
                            .foregroundStyle(.secondary)
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

            CommitListView(commits: commits)
        }
    }

    private var metricSummary: String {
        if workSnapshot.mode == .diffBacked {
            return "\(workSnapshot.workUnits.formatted()) work units, +\(workSnapshot.additions.formatted()) -\(workSnapshot.deletions.formatted()), \(workSnapshot.changedFiles.formatted()) files"
        }
        let coverage = workSnapshot.coverage.formatted(.percent.precision(.fractionLength(0)))
        return "\(commits.count.formatted()) commits, \(coverage) stats coverage"
    }
}

private struct SummaryView: View {
    let summary: DailyJournalSummaryRecord

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.title)
                        .kit941Font(.title, weight: .bold)
                    Spacer(minLength: Kit941.Spacing.sm)
                    Text(summary.generatedAt, style: .time)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(summary.narrative)
                    .kit941Font(.body)
                    .foregroundStyle(.primary)

                if !summary.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                        ForEach(summary.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: Kit941.Spacing.sm) {
                                Circle()
                                    .fill(AppSurface.accent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                                Text(bullet)
                                    .kit941Font(.body)
                            }
                        }
                    }
                }

                if !summary.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(summary.tags, id: \.self) { tag in
                            Text(tag)
                                .kit941Font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                    }
                }

                Text("\(summary.sourceCommitIDs.count) source commits - \(summary.modelName)")
                    .kit941Font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(commits) { commit in
                        CommitRow(commit: commit)
                        if commit.id != commits.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
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
                    .fill(Color.primary.opacity(0.12))
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
                .foregroundStyle(.secondary)

                Text(statsLabel)
                    .kit941Font(.caption)
                    .foregroundStyle(statsColor)

                if !commit.messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(commit.messageBody)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Kit941.Spacing.md)
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
        commit.hasDiffStats ? AppSurface.accent : .secondary
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
