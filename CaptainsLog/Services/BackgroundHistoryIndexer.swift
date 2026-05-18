import Foundation
import OSLog
import SwiftData

#if os(iOS)
@preconcurrency import BackgroundTasks
import UIKit
#endif

enum BackgroundHistoryIndexer {
    static let taskIdentifier = "com.blakecrosley.captainslog.history-index"
    static let defaultEarliestDelay: TimeInterval = 30 * 60
    static let lookbackDays = 7_300

    fileprivate static let logger = Logger(subsystem: "com.blakecrosley.captainslog", category: "background-index")

    @discardableResult
    static func schedule(
        earliestBeginDate: Date = Date().addingTimeInterval(defaultEarliestDelay)
    ) -> Bool {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background history index")
            return true
        } catch {
            logger.error("Failed to schedule background history index: \(error.localizedDescription, privacy: .private)")
            return false
        }
        #else
        return false
        #endif
    }

    static func cancelPending() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.info("Canceled pending background history index")
        #endif
    }

    @MainActor
    static func run(modelContainer: ModelContainer) async -> Bool {
        let modelContext = ModelContext(modelContainer)
        let appModel = AppModel()
        appModel.configure(modelContext: modelContext)
        await appModel.loadSession()

        guard appModel.isSignedIn else {
            logger.info("Skipped background history index because no GitHub session is available")
            cancelPending()
            return false
        }

        await appModel.syncLatestIfStale()

        guard appModel.isSignedIn else {
            logger.info("Skipped background history index because GitHub session was lost during latest sync")
            cancelPending()
            return false
        }

        do {
            guard try appModel.hasHistoricalAnalyticsBackfillWork(lookbackDays: lookbackDays) else {
                logger.info("Skipped background history index because selected history is complete")
                cancelPending()
                return true
            }
        } catch {
            logger.error("Failed to inspect background history backlog: \(error.localizedDescription, privacy: .private)")
            return false
        }

        await appModel.fullSyncSelectedRepositories(lookbackDays: lookbackDays)

        do {
            if try appModel.hasHistoricalAnalyticsBackfillWork(lookbackDays: lookbackDays), appModel.isSignedIn {
                schedule()
            } else {
                cancelPending()
            }
        } catch {
            logger.error("Failed to inspect remaining background history backlog: \(error.localizedDescription, privacy: .private)")
        }

        return !Task.isCancelled
    }
}

#if os(iOS)
@MainActor
final class CaptainsLogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard !CaptainsLogApp.isUITesting else {
            return true
        }

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundHistoryIndexer.taskIdentifier,
            using: .main
        ) { task in
            BackgroundHistoryIndexer.schedule()

            let work = Task { @MainActor in
                let success = await BackgroundHistoryIndexer.run(modelContainer: CaptainsLogApp.sharedModelContainer)
                task.setTaskCompleted(success: success)
            }

            task.expirationHandler = {
                work.cancel()
            }
        }

        if !registered {
            BackgroundHistoryIndexer.logger.error("Failed to register background history index task")
        }

        return true
    }
}
#endif
