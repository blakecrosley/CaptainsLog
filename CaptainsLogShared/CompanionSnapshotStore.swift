import Combine
import Foundation

#if os(watchOS)
@preconcurrency import WatchConnectivity
#endif

@MainActor
final class CompanionSnapshotStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: CompanionSnapshot

    private let ubiquitousStore: NSUbiquitousKeyValueStore
    private var didStart = false

    init(ubiquitousStore: NSUbiquitousKeyValueStore = .default) {
        self.ubiquitousStore = ubiquitousStore
        self.snapshot = Self.loadSnapshot(from: ubiquitousStore) ?? .placeholder
        super.init()
    }

    func start() {
        guard !didStart else {
            refreshFromUbiquitousStore()
            return
        }

        didStart = true
        refreshFromUbiquitousStore()

        #if os(watchOS)
        activateWatchSession()
        requestSnapshotFromPhone()
        #endif
    }

    func refreshFromUbiquitousStore() {
        ubiquitousStore.synchronize()
        guard let snapshot = Self.loadSnapshot(from: ubiquitousStore) else {
            return
        }
        self.snapshot = snapshot
    }

    func save(_ snapshot: CompanionSnapshot) {
        self.snapshot = snapshot
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        ubiquitousStore.set(data, forKey: CompanionSnapshotSync.ubiquitousStoreKey)
        ubiquitousStore.synchronize()
    }

    private static func loadSnapshot(from store: NSUbiquitousKeyValueStore) -> CompanionSnapshot? {
        guard let data = store.data(forKey: CompanionSnapshotSync.ubiquitousStoreKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CompanionSnapshot.self, from: data)
    }
}

#if os(watchOS)
extension CompanionSnapshotStore: WCSessionDelegate {
    private func activateWatchSession() {
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func requestSnapshotFromPhone() {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            return
        }

        WCSession.default.sendMessage(
            CompanionSnapshotSync.requestSnapshotPayload(),
            replyHandler: nil,
            errorHandler: nil
        )
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else {
            return
        }
        Task { @MainActor in
            requestSnapshotFromPhone()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveSnapshotPayload(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveSnapshotPayload(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        receiveSnapshotPayload(message)
        replyHandler([:])
    }

    private nonisolated func receiveSnapshotPayload(_ payload: [String: Any]) {
        guard let snapshot = CompanionSnapshotSync.snapshot(from: payload) else {
            return
        }
        Task { @MainActor in
            save(snapshot)
        }
    }
}
#endif
