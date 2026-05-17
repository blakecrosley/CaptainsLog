import SwiftData
import SwiftUI
import Kit941

@main
@MainActor
struct CaptainsLogApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CaptainsLogAppDelegate.self) private var appDelegate
    #endif
    static let sharedModelContainer = makeModelContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .kit941Theme(CaptainsLogTheme(theme: selectedTheme))
                .tint(selectedTheme.accent)
                .preferredColorScheme(selectedTheme.prefersDark ? .dark : .light)
                #if DEBUG
                .task {
                    seedOpenAICredentialFromLaunchEnvironmentIfPresent()
                }
                #endif
        }
        .modelContainer(Self.sharedModelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            let schema = Schema([
                GitHubAccountRecord.self,
                GitRepositoryRecord.self,
                GitCommitRecord.self,
                DailyJournalSummaryRecord.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create Captain's Log model container: \(error)")
        }
    }

    private var selectedTheme: AppSurface.Theme {
        AppSurface.defaultTheme
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["CAPTAINS_LOG_UI_TESTING"] == "1"
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
        debugPrint("Skipped debug OpenAI key seed: \(violation)")
        return
    }

    guard AIProviderCredentialStore.shared.saveKey(key, for: .openai) else {
        debugPrint("Skipped debug OpenAI key seed: Keychain save failed")
        return
    }

    debugPrint("Seeded OpenAI key from debug launch environment")
}
#endif

private struct CaptainsLogTheme: Kit941Theme {
    let theme: AppSurface.Theme

    var accent: Color { theme.accent }
    var primaryContent: Color { theme.primaryText }
    var secondaryContent: Color { theme.secondaryText }
    var danger: Color { theme.danger }
    var surfaceFill: Color { theme.panelBase }
    var surfaceStroke: Color { theme.panelStroke(highlighted: false) }
    var fontFamily: Kit941.FontFamily { theme.fontFamily }
    var cornerStyle: Kit941.CornerStyle { .continuous }
    var motionFeel: Kit941.MotionFeel { .system }
}
