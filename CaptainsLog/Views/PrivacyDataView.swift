import SwiftUI
import Kit941

struct PrivacyDataView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let isSignedIn: Bool
    let activeLogin: String?
    let selectedRepositoryCount: Int
    let importedCommitCount: Int
    let journalCount: Int
    let hasCloudAIKey: Bool
    let preferredProviderName: String
    let onClearImportedHistory: () throws -> LocalHistoryDeletionResult

    @State private var isConfirmingClearHistory = false
    @State private var clearHistoryMessage: String?
    @State private var clearHistoryIsError = false

    var body: some View {
        ScrollView {
            content
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .appReadablePage(compactMaxWidth: 680, regularMaxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppSurface.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Privacy & Data")
        .confirmationDialog("Clear imported history?", isPresented: $isConfirmingClearHistory, titleVisibility: .visible) {
            Button("Clear Imported History", role: .destructive) {
                clearImportedHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes imported commits, line stats, and generated journals from this device. GitHub access, selected repositories, and AI keys stay attached.")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var content: some View {
        Group {
            if usesWideLayout {
                HStack(alignment: .top, spacing: Kit941.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                        summaryCard
                        dataFlowCard
                        reviewNoteCard
                    }

                    VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                        publicLinksCard
                        controlsCard
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    summaryCard
                    dataFlowCard
                    publicLinksCard
                    controlsCard
                    reviewNoteCard
                }
            }
        }
    }

    private var summaryCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppSurface.accent)
                        .frame(width: 42, height: 42)
                        .background(AppSurface.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local first, explicit cloud calls")
                            .kit941Font(.title, weight: .semibold)
                            .foregroundStyle(AppSurface.primaryText)
                        Text(summaryText)
                            .kit941Font(.body)
                            .foregroundStyle(AppSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dataFlowCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text("What Leaves the Device")
                    .kit941Font(.title, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)

                PrivacyDataRow(
                    icon: "arrow.triangle.branch",
                    title: "GitHub",
                    description: "Repository lists, commit history, and diff stats are requested from GitHub for selected repositories."
                )

                PrivacyDataRow(
                    icon: hasCloudAIKey ? "sparkles" : "apple.intelligence",
                    title: aiProviderTitle,
                    description: aiProviderDescription
                )

                PrivacyDataRow(
                    icon: "chart.bar.doc.horizontal",
                    title: "No analytics SDK",
                    description: "This build has no advertising, tracking, or product analytics SDK in the app target."
                )
            }
        }
    }

    private var controlsCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text("User Controls")
                    .kit941Font(.title, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)

                PrivacyDataRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Disconnect GitHub",
                    description: "Sign out removes the saved GitHub session from this device. GitHub access can also be changed from GitHub."
                )

                PrivacyDataRow(
                    icon: "key.slash",
                    title: "Remove AI keys",
                    description: "Provider keys live in Keychain and can be deleted from AI provider settings."
                )

                PrivacyDataRow(
                    icon: "externaldrive",
                    title: "Local history",
                    description: localHistoryDescription
                )

                Divider()
                    .overlay(AppSurface.divider.opacity(0.6))

                AppActionRow(
                    title: "Clear Imported History",
                    description: "Remove commits, line stats, and journals from this device while keeping account setup.",
                    systemImage: "trash",
                    isDestructive: true,
                    isDisabled: importedCommitCount == 0 && journalCount == 0,
                    showsChevron: false,
                    action: {
                        isConfirmingClearHistory = true
                    }
                )

                if let clearHistoryMessage {
                    Label(clearHistoryMessage, systemImage: clearHistoryIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .kit941Font(.caption)
                        .foregroundStyle(clearHistoryIsError ? AppSurface.warning : AppSurface.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var publicLinksCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text("Policies & Support")
                    .kit941Font(.title, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)

                PolicyLinkRow(
                    title: "Privacy Policy",
                    description: "Read what data Captain's Log uses and where it is stored.",
                    systemImage: "doc.text.magnifyingglass",
                    action: {
                        openURL(Self.privacyPolicyURL)
                    }
                )

                Divider()
                    .overlay(AppSurface.divider.opacity(0.55))

                PolicyLinkRow(
                    title: "Support",
                    description: "Get help with GitHub access, local history, or AI keys.",
                    systemImage: "questionmark.bubble",
                    action: {
                        openURL(Self.supportURL)
                    }
                )
            }
        }
    }

    private var reviewNoteCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                Text("Why GitHub Sign-In?")
                    .kit941Font(.label, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)
                Text("Captain's Log connects to GitHub only so you can choose repositories and import your commit history. It does not create a separate social account.")
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localHistoryDescription: String {
        let commitWord = importedCommitCount == 1 ? "commit" : "commits"
        let journalWord = journalCount == 1 ? "journal" : "journals"
        return "\(importedCommitCount.formatted()) imported \(commitWord) and \(journalCount.formatted()) generated \(journalWord) are stored on this device."
    }

    private var summaryText: String {
        if isSignedIn {
            let login = activeLogin ?? "GitHub"
            let repoWord = selectedRepositoryCount == 1 ? "repository" : "repositories"
            return "\(login) is connected with \(selectedRepositoryCount.formatted()) selected \(repoWord). Tokens and keys stay in Keychain."
        }
        return "Connect GitHub only when you want to sync repository history. Demo data stays local."
    }

    private var aiProviderTitle: String {
        hasCloudAIKey ? preferredProviderName : "Apple Foundation Models"
    }

    private var aiProviderDescription: String {
        if hasCloudAIKey {
            return "When you generate a journal, selected commit evidence is sent directly to \(preferredProviderName) using your saved key."
        }
        return "Journal generation uses the on-device Apple model when available."
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private static let privacyPolicyURL = URL(string: "https://blakecrosley.com/captains-log/privacy")!
    private static let supportURL = URL(string: "https://blakecrosley.com/captains-log/support")!

    private func clearImportedHistory() {
        do {
            let result = try onClearImportedHistory()
            clearHistoryMessage = result.message
            clearHistoryIsError = false
        } catch {
            clearHistoryMessage = error.localizedDescription
            clearHistoryIsError = true
        }
    }
}

private struct PolicyLinkRow: View {
    let title: String
    let description: String
    let systemImage: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppSurface.accent)
                    .frame(width: 30, height: 30)
                    .background(AppSurface.accent.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                    Text(description)
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Kit941.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppSurface.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}

private struct PrivacyDataRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Kit941.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppSurface.accent)
                .frame(width: 28, height: 28)
                .background(AppSurface.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .kit941Font(.label, weight: .semibold)
                    .foregroundStyle(AppSurface.primaryText)
                Text(description)
                    .kit941Font(.caption)
                    .foregroundStyle(AppSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
