import Foundation

enum WorkIdentityScope: String, CaseIterable, Identifiable {
    case mineAndAliases
    case allSelectedRepos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mineAndAliases: "Mine"
        case .allSelectedRepos: "All"
        }
    }

    var label: String {
        switch self {
        case .mineAndAliases: "Mine + aliases"
        case .allSelectedRepos: "All selected repo activity"
        }
    }
}

struct WorkIdentitySelection: Equatable {
    let activeLogin: String?
    let scope: WorkIdentityScope
    let aliases: Set<String>

    init(
        activeLogin: String?,
        scope: WorkIdentityScope,
        aliases: Set<String> = []
    ) {
        self.activeLogin = activeLogin
        self.scope = scope
        self.aliases = Set(aliases.map(Self.normalize).filter { !$0.isEmpty })
    }

    var normalizedActiveLogin: String? {
        activeLogin.map(Self.normalize).flatMap { $0.isEmpty ? nil : $0 }
    }

    var normalizedAuthorLogins: Set<String> {
        var logins = aliases
        if let normalizedActiveLogin {
            logins.insert(normalizedActiveLogin)
        }
        return logins
    }

    var aliasCount: Int {
        aliases.count
    }

    func includes(authorLogin: String?) -> Bool {
        switch scope {
        case .allSelectedRepos:
            return true
        case .mineAndAliases:
            guard let authorLogin else {
                return true
            }
            let allowedLogins = normalizedAuthorLogins
            guard !allowedLogins.isEmpty else {
                return true
            }
            return allowedLogins.contains(Self.normalize(authorLogin))
        }
    }

    static func aliases(from text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
                .map(normalize)
                .filter { !$0.isEmpty }
        )
    }

    static func aliasesText(from aliases: Set<String>) -> String {
        aliases.sorted().joined(separator: "\n")
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum WorkIdentityPreferences {
    static let scopeKey = "workIdentity.scope"

    static func aliasesKey(for login: String?) -> String {
        let login = login.map(WorkIdentitySelection.normalize).flatMap { $0.isEmpty ? nil : $0 } ?? "global"
        return "workIdentity.aliases.\(login)"
    }

    static func loadAliasesText(for login: String?, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: aliasesKey(for: login)) ?? ""
    }

    static func saveAliasesText(_ text: String, for login: String?, defaults: UserDefaults = .standard) {
        let aliases = WorkIdentitySelection.aliases(from: text)
        defaults.set(WorkIdentitySelection.aliasesText(from: aliases), forKey: aliasesKey(for: login))
    }
}
