import Foundation

#if os(iOS)
@preconcurrency import WatchConnectivity
#endif

@MainActor
final class CompanionSnapshotPublisher: NSObject {
    static let shared = CompanionSnapshotPublisher()

    private let store = CompanionSnapshotStore()
    private var didStart = false

    private override init() {
        super.init()
    }

    func publish(_ snapshot: CompanionSnapshot) {
        start()
        store.save(snapshot)

        #if os(iOS)
        sendSnapshotToWatch(snapshot)
        #endif
    }

    private func start() {
        guard !didStart else {
            return
        }
        didStart = true
        store.start()

        #if os(iOS)
        activateWatchSession()
        #endif
    }
}

#if os(iOS)
extension CompanionSnapshotPublisher: WCSessionDelegate {
    private func activateWatchSession() {
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func sendSnapshotToWatch(_ snapshot: CompanionSnapshot) {
        guard WCSession.isSupported() else {
            return
        }

        let payload = CompanionSnapshotSync.payload(for: snapshot)
        guard !payload.isEmpty else {
            return
        }

        let session = WCSession.default
        if session.activationState == .activated {
            guard session.isPaired else {
                return
            }
            try? session.updateApplicationContext(payload)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
        } else {
            activateWatchSession()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            activateWatchSession()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard CompanionSnapshotSync.isSnapshotRequest(message) else {
            return
        }

        Task { @MainActor in
            sendSnapshotToWatch(store.snapshot)
        }
    }
}
#endif
