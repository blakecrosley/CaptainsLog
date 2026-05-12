import SwiftUI
import Kit941

struct GitHubAvatarView: View {
    let url: URL?
    let login: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Text(loginInitial)
            .kit941Font(.label, weight: .semibold)
            .foregroundStyle(.secondary)
    }

    private var loginInitial: String {
        guard let first = login?.first else {
            return "G"
        }
        return String(first).uppercased()
    }
}

struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss

    let accounts: [GitHubAccountRecord]
    let authState: AppModel.AuthState
    let clientID: String
    let authMessage: String
    let activeLogin: String?
    let onSwitch: @MainActor @Sendable (GitHubAccountRecord) -> Void
    let onAddAccount: @MainActor @Sendable () -> Void
    let onCompleteSignIn: @MainActor @Sendable () -> Void
    let onSignOut: @MainActor @Sendable () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    accountList

                    if isAuthorizing {
                        GitHubAuthCard(
                            authState: authState,
                            clientID: clientID,
                            authMessage: authMessage,
                            onConnect: onAddAccount,
                            onCompleteSignIn: onCompleteSignIn,
                            onSeedDemo: {}
                        )
                    } else {
                        addAccountCard
                    }
                }
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.background.ignoresSafeArea())
            .navigationTitle("GitHub Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var accountList: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accounts")
                        .kit941Font(.title, weight: .semibold)
                    Text(accounts.isEmpty ? "No GitHub account stored" : "\(accounts.count.formatted()) available")
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }

                if accounts.isEmpty {
                    Text("Sign in with GitHub to sync repositories.")
                        .kit941Font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(accounts) { account in
                            accountRow(account)
                            if account.login != accounts.last?.login {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var addAccountCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                Text("Add Account")
                    .kit941Font(.title, weight: .semibold)
                Text("Connect another GitHub account with Device Flow. The overview uses the active account's commits.")
                    .kit941Font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: Kit941.Spacing.sm) {
                    Kit941.Button {
                        await MainActor.run { onAddAccount() }
                    } label: {
                        Label("Add GitHub Account", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(clientID.isEmpty)

                    if activeLogin != nil {
                        Kit941.Button(role: .plain) {
                            await MainActor.run { onSignOut() }
                        } label: {
                            Text("Sign out")
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ account: GitHubAccountRecord) -> some View {
        Button {
            onSwitch(account)
            dismiss()
        } label: {
            HStack(spacing: Kit941.Spacing.sm) {
                GitHubAvatarView(url: account.avatarURL, login: account.login)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.login)
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(.primary)
                    if let name = account.name, !name.isEmpty {
                        Text(name)
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("GitHub")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if account.login == activeLogin || account.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppSurface.accent)
                }
            }
            .padding(.vertical, Kit941.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isAuthorizing: Bool {
        switch authState {
        case .requestingCode, .waitingForUser, .completingSignIn:
            return true
        default:
            return false
        }
    }
}
