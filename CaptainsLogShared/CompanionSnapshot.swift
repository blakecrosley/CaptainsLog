import Foundation

struct CompanionSnapshot: Codable, Equatable {
    struct Card: Codable, Equatable, Identifiable {
        var id: String { title }

        let title: String
        let value: String
        let detail: String
    }

    let schemaVersion: Int
    let generatedAt: Date
    let primary: Card
    let week: Card
    let journal: Card
    let repositories: Card

    static let placeholder = CompanionSnapshot(
        schemaVersion: 1,
        generatedAt: .distantPast,
        primary: Card(
            title: "Today",
            value: "Waiting",
            detail: "Open the main app to sync your latest GitHub work."
        ),
        week: Card(
            title: "Week",
            value: "No snapshot",
            detail: "The main app sends a private aggregate summary."
        ),
        journal: Card(
            title: "Journal",
            value: "Main app",
            detail: "Generate and review journal entries on iPhone, iPad, or Mac."
        ),
        repositories: Card(
            title: "Repos",
            value: "Main app",
            detail: "GitHub credentials stay in the main app."
        )
    )

    var isPlaceholder: Bool {
        generatedAt == .distantPast
    }

    var refreshedText: String {
        guard !isPlaceholder else {
            return "Open the main app to sync"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: generatedAt, relativeTo: Date()))"
    }
}

enum CompanionSnapshotSync {
    static let ubiquitousStoreKey = "captainsLog.companion.snapshot.v1"
    static let payloadDataKey = "captainsLogSnapshotData"
    static let payloadTypeKey = "captainsLogMessageType"
    static let snapshotMessageType = "snapshot"
    static let requestSnapshotMessageType = "requestSnapshot"

    nonisolated static func payload(for snapshot: CompanionSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return [:]
        }
        return [
            payloadTypeKey: snapshotMessageType,
            payloadDataKey: data
        ]
    }

    nonisolated static func requestSnapshotPayload() -> [String: Any] {
        [payloadTypeKey: requestSnapshotMessageType]
    }

    nonisolated static func isSnapshotRequest(_ payload: [String: Any]) -> Bool {
        payload[payloadTypeKey] as? String == requestSnapshotMessageType
    }

    nonisolated static func snapshot(from payload: [String: Any]) -> CompanionSnapshot? {
        let data: Data?
        if let payloadData = payload[payloadDataKey] as? Data {
            data = payloadData
        } else if let payloadData = payload[payloadDataKey] as? NSData {
            data = payloadData as Data
        } else {
            data = nil
        }

        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(CompanionSnapshot.self, from: data)
    }
}
