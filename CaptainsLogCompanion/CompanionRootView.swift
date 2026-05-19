import SwiftUI

struct CompanionRootView: View {
    @StateObject private var snapshotStore = CompanionSnapshotStore()

    var body: some View {
        Group {
            #if os(watchOS)
            WatchCompanionView()
            #elseif os(tvOS)
            TVCompanionView()
            #else
            EmptyView()
            #endif
        }
        .environmentObject(snapshotStore)
        .onAppear {
            snapshotStore.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            snapshotStore.refreshFromUbiquitousStore()
        }
    }
}

#if os(watchOS)
private struct WatchCompanionView: View {
    @EnvironmentObject private var snapshotStore: CompanionSnapshotStore

    var body: some View {
        let snapshot = snapshotStore.snapshot

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
                        card: snapshot.primary
                    )

                    VStack(spacing: 8) {
                        WatchMetricRow(card: snapshot.week)
                        WatchMetricRow(card: snapshot.journal)
                        WatchMetricRow(card: snapshot.repositories)
                    }

                    Text(snapshot.refreshedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if snapshot.isPlaceholder {
                        Text("Open the main app to send a private aggregate snapshot.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Log")
        }
    }
}

private struct WatchStatusCard: View {
    let card: CompanionSnapshot.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.value)
                .font(.title3.weight(.semibold))
            Text(card.detail)
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
    let card: CompanionSnapshot.Card

    var body: some View {
        HStack {
            Text(card.title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(card.value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }
}
#endif

#if os(tvOS)
private struct TVCompanionView: View {
    @EnvironmentObject private var snapshotStore: CompanionSnapshotStore

    var body: some View {
        let snapshot = snapshotStore.snapshot
        let cards = [
            snapshot.primary,
            snapshot.week,
            snapshot.journal,
            snapshot.repositories
        ]

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

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(760), spacing: 28),
                        GridItem(.fixed(760), spacing: 28)
                    ],
                    spacing: 28
                ) {
                    ForEach(cards) { card in
                        TVStatusCard(card: card)
                    }
                }

                HStack(spacing: 18) {
                    Label("No GitHub credentials on Apple TV", systemImage: "lock.shield")
                    Label("Use the main app for setup", systemImage: "iphone")
                    Label("iCloud keeps the read-only snapshot current", systemImage: "icloud")
                }
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

                Text(snapshot.refreshedText)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct TVStatusCard: View {
    let card: CompanionSnapshot.Card

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
        .frame(width: 700, height: 170, alignment: .topLeading)
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
