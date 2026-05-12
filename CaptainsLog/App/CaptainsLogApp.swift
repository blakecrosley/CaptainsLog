import SwiftData
import SwiftUI
import Kit941

@main
struct CaptainsLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .kit941Theme(CaptainsLogTheme())
                #if DEBUG
                .task {
                    seedOpenAICredentialFromLaunchEnvironmentIfPresent()
                }
                #endif
        }
        .modelContainer(for: [
            GitHubAccountRecord.self,
            GitRepositoryRecord.self,
            GitCommitRecord.self,
            DailyJournalSummaryRecord.self
        ])
    }
}

#if DEBUG
private func seedOpenAICredentialFromLaunchEnvironmentIfPresent() {
    let environment = ProcessInfo.processInfo.environment
    let rawKey = environment["CAPTAINS_LOG_DEBUG_OPENAI_API_KEY"] ?? environment["REPS_DEBUG_OPENAI_API_KEY"]
    guard let rawKey else {
        return
    }

    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
        return
    }

    if let violation = AIProvider.openai.formatViolation(for: key) {
        debugPrint("Skipped debug OpenAI BYOK seed: \(violation)")
        return
    }

    guard AIProviderCredentialStore.shared.saveKey(key, for: .openai) else {
        debugPrint("Skipped debug OpenAI BYOK seed: Keychain save failed")
        return
    }

    debugPrint("Seeded OpenAI BYOK credential from debug launch environment")
}
#endif

private struct CaptainsLogTheme: Kit941Theme {
    var accent: Color { Color(red: 0.10, green: 0.43, blue: 0.26) }
    var fontFamily: Kit941.FontFamily { .system }
    var cornerStyle: Kit941.CornerStyle { .continuous }
    var motionFeel: Kit941.MotionFeel { .system }
}
