import SwiftUI
import Kit941

struct GitHubAuthCard: View {
    @Environment(\.openURL) private var openURL

    let authState: AppModel.AuthState
    let clientID: String
    let authMessage: String
    let onConnect: @MainActor @Sendable () -> Void
    let onCompleteSignIn: @MainActor @Sendable () -> Void
    let onSeedDemo: @MainActor @Sendable () -> Void

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppSurface.accent)
                    Text("Connect GitHub")
                        .kit941Font(.title, weight: .semibold)
                }

                Text("Captain's Log uses GitHub Device Flow, stores the token in Keychain, and only sees repositories where the GitHub App is installed.")
                    .kit941Font(.body)
                    .foregroundStyle(.secondary)

                stateContent

                HStack(spacing: Kit941.Spacing.sm) {
                    actions
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch authState {
        case .signedOut:
            if clientID.isEmpty {
                VStack(alignment: .leading, spacing: Kit941.Spacing.xs) {
                    Label("GitHub sign-in is not configured yet", systemImage: "exclamationmark.triangle")
                        .kit941Font(.label)
                        .foregroundStyle(Kit941.Status.warning)
                    Text("Register the GitHub App, enable Device Flow, and set GITHUB_CLIENT_ID in the build.")
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .requestingCode:
            Label("Requesting a GitHub code", systemImage: "hourglass")
                .kit941Font(.label)
                .foregroundStyle(.secondary)
        case .waitingForUser(let code):
            codeContent(code, isChecking: false)
        case .completingSignIn(let code):
            codeContent(code, isChecking: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .kit941Font(.label)
                .foregroundStyle(Kit941.Status.danger)
        case .signedIn:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch authState {
        case .signedOut, .failed:
            Kit941.Button {
                await MainActor.run { onConnect() }
            } label: {
                Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
            }
            .disabled(clientID.isEmpty)

            Kit941.Button(role: .secondary) {
                await MainActor.run { onSeedDemo() }
            } label: {
                Label("Demo", systemImage: "square.grid.3x3")
            }
        case .requestingCode:
            Kit941.Button {
            } label: {
                Label("Requesting Code", systemImage: "hourglass")
            }
            .disabled(true)
        case .waitingForUser(let code):
            Kit941.Button {
                await MainActor.run {
                    ClipboardService.copy(code.userCode)
                    openURL(code.verificationURI)
                }
            } label: {
                Label("Copy & Open GitHub", systemImage: "doc.on.doc")
            }

            Kit941.Button(role: .secondary) {
                await MainActor.run { onCompleteSignIn() }
            } label: {
                Label("Check Authorization", systemImage: "checkmark.circle")
            }
        case .completingSignIn:
            Kit941.Button {
            } label: {
                Label("Checking", systemImage: "hourglass")
            }
            .disabled(true)
        case .signedIn:
            EmptyView()
        }
    }

    private func codeContent(_ code: GitHubDeviceCodeResponse, isChecking: Bool) -> some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text(code.userCode)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.sm)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Kit941.Radius.md))
                .textSelection(.enabled)

            Text("Copy this code, authorize at github.com/login/device, then return and check authorization.")
                .kit941Font(.caption)
                .foregroundStyle(.secondary)

            if isChecking {
                Label("Checking GitHub authorization", systemImage: "hourglass")
                    .kit941Font(.label)
                    .foregroundStyle(.secondary)
            } else if !authMessage.isEmpty {
                Label(authMessage, systemImage: "exclamationmark.triangle")
                    .kit941Font(.label)
                    .foregroundStyle(Kit941.Status.warning)
            }
        }
    }
}

struct RepositoryPanel: View {
    let repositories: [GitRepositoryRecord]
    let isSyncing: Bool
    let syncMessage: String
    let importedCommitCount: Int
    let appInstallURL: URL?
    let onRefreshRepos: @MainActor @Sendable () -> Void
    let onSyncSelected: @MainActor @Sendable () -> Void
    let onFullSync: @MainActor @Sendable () -> Void
    let onInstallApp: @MainActor @Sendable () -> Void

    var body: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Repositories")
                            .kit941Font(.title, weight: .semibold)
                        Text("\(selectedCount) selected")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Kit941.Spacing.sm)

                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if repositories.isEmpty {
                    VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                        Text("Approve access to all repositories or selected repositories in GitHub, then refresh.")
                            .kit941Font(.body)
                            .foregroundStyle(.secondary)

                        if appInstallURL != nil {
                            Kit941.Button(role: .secondary) {
                                await MainActor.run { onInstallApp() }
                            } label: {
                                Label("Approve Access", systemImage: "checklist")
                            }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(repositories) { repo in
                                RepositoryToggleRow(repository: repo)
                                if repo.id != repositories.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(height: repositoryListHeight)
                    .clipped()
                    .scrollIndicators(.visible)
                }

                if !syncMessage.isEmpty {
                    Text(syncMessage)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: Kit941.Spacing.sm) {
                    Kit941.Button(role: .secondary) {
                        await MainActor.run { onRefreshRepos() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Kit941.Button {
                        await MainActor.run { onSyncSelected() }
                    } label: {
                        Label("Sync Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(repositories.isEmpty || selectedCount == 0)

                    Kit941.Button(role: .secondary) {
                        await MainActor.run { onFullSync() }
                    } label: {
                        Label("Backfill All", systemImage: "square.and.arrow.down")
                    }
                    .disabled(repositories.isEmpty || selectedCount == 0)
                }
            }
        }
    }

    private var selectedCount: Int {
        repositories.filter(\.isSelected).count
    }

    private var repositoryListHeight: CGFloat {
        min(CGFloat(repositories.count) * 58, 320)
    }
}

private struct RepositoryToggleRow: View {
    @Bindable var repository: GitRepositoryRecord

    var body: some View {
        Toggle(isOn: $repository.isSelected) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repository.fullName)
                    .kit941Font(.label, weight: .semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(repository.isPrivate ? "Private" : "Public")
                    if let pushedAt = repository.pushedAt {
                        Text("Updated \(pushedAt, style: .relative)")
                    }
                }
                .kit941Font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, Kit941.Spacing.sm)
    }
}
