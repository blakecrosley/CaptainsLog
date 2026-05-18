import Foundation
import Security

enum KeychainTokenStore {
    private static let service = "com.blakecrosley.captainslog.github"
    private static let account = "oauth-token"
    private static let activeAccount = "active-login"
    private static let accountTokenPrefix = "oauth-token:"
    private static let accountSessionPrefix = "oauth-session:"

    static func readToken() throws -> String? {
        if let session = try readSession() {
            return session.accessToken
        }
        return nil
    }

    static func readSession() throws -> GitHubOAuthSession? {
        if let activeLogin = try activeLogin(),
           let session = try readSession(login: activeLogin) {
            return session
        }
        if let token = try readString(account: account) {
            return GitHubOAuthSession(accessToken: token)
        }
        return nil
    }

    static func readToken(login: String) throws -> String? {
        if let session = try readSession(login: login) {
            return session.accessToken
        }
        return nil
    }

    static func readSession(login: String) throws -> GitHubOAuthSession? {
        if let data = try readData(account: sessionAccount(login: login)) {
            return try JSONDecoder().decode(GitHubOAuthSession.self, from: data)
        }
        if let token = try readString(account: tokenAccount(login: login)) {
            return GitHubOAuthSession(accessToken: token)
        }
        return nil
    }

    static func activeLogin() throws -> String? {
        try readString(account: activeAccount)
    }

    static func saveToken(_ token: String, login: String) throws {
        try saveSession(GitHubOAuthSession(accessToken: token), login: login)
    }

    static func saveSession(_ session: GitHubOAuthSession, login: String) throws {
        let data = try JSONEncoder().encode(session)
        try saveData(data, account: sessionAccount(login: login))
        try saveString(session.accessToken, account: tokenAccount(login: login))
        try saveActiveLogin(login)
    }

    static func saveToken(_ token: String) throws {
        try saveString(token, account: account)
    }

    static func saveActiveLogin(_ login: String) throws {
        try saveString(login, account: activeAccount)
    }

    static func deleteToken(login: String) throws {
        try deleteString(account: sessionAccount(login: login))
        try deleteString(account: tokenAccount(login: login))
        if try activeLogin() == login {
            try deleteString(account: activeAccount)
        }
    }

    static func deleteToken() throws {
        if let login = try activeLogin() {
            try deleteString(account: sessionAccount(login: login))
            try deleteString(account: tokenAccount(login: login))
        }
        try deleteString(account: activeAccount)
        try deleteString(account: account)
    }

    private static func tokenAccount(login: String) -> String {
        accountTokenPrefix + login
    }

    private static func sessionAccount(login: String) -> String {
        accountSessionPrefix + login
    }

    private static func readString(account: String) throws -> String? {
        guard let data = try readData(account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func readData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        return data
    }

    private static func saveString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try saveData(data, account: account)
    }

    private static func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw KeychainError.unhandled(status)
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
    }

    private static func deleteString(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandled(OSStatus)

    var isMissingEntitlement: Bool {
        guard case .unhandled(let status) = self else {
            return false
        }
        return status == errSecMissingEntitlement
    }

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The stored GitHub token could not be read."
        case .unhandled(let status):
            return "Keychain returned status \(status)."
        }
    }
}
