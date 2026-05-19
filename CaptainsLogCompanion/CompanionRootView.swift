import SwiftUI

struct CompanionRootView: View {
    var body: some View {
        #if os(watchOS)
        WatchCompanionView()
        #elseif os(tvOS)
        TVCompanionView()
        #else
        EmptyView()
        #endif
    }
}

#if os(watchOS)
private struct WatchCompanionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Captain's Log")
                            .font(.headline)
                        Text("Sync from iPhone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    WatchStatusCard(
                        title: "Today",
                        value: "Waiting",
                        detail: "Open the main app to refresh GitHub work."
                    )

                    VStack(spacing: 8) {
                        WatchMetricRow(title: "Journal", value: "Ready")
                        WatchMetricRow(title: "Repos", value: "Main app")
                        WatchMetricRow(title: "AI", value: "On device")
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Log")
        }
    }
}

private struct WatchStatusCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WatchMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }
}
#endif

#if os(tvOS)
private struct TVCompanionView: View {
    private let cards = [
        TVCompanionCard(title: "Today", value: "Sync pending", detail: "Refresh from iPhone, iPad, or Mac"),
        TVCompanionCard(title: "Week", value: "Journal ready", detail: "Review summaries on the main app"),
        TVCompanionCard(title: "Repos", value: "Selected on main", detail: "GitHub access stays off the shared screen")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.05),
                    Color(red: 0.05, green: 0.14, blue: 0.11),
                    Color(red: 0.12, green: 0.10, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Captain's Log")
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                    Text("A quiet work dashboard for the room.")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 28) {
                    ForEach(cards) { card in
                        TVStatusCard(card: card)
                    }
                }

                HStack(spacing: 18) {
                    Label("No GitHub credentials on Apple TV", systemImage: "lock.shield")
                    Label("Use the main app for sync", systemImage: "arrow.triangle.2.circlepath")
                    Label("Built for read-only review", systemImage: "chart.bar")
                }
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct TVCompanionCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

private struct TVStatusCard: View {
    let card: TVCompanionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(card.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(card.value)
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(card.detail)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 470, height: 240, alignment: .topLeading)
        .padding(30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .focusable(true)
    }
}
#endif
