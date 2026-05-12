import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable {
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        }
    }

    var keychainAccount: String {
        rawValue
    }

    func formatViolation(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Key is empty."
        }
        return trimmed.hasPrefix("sk-") ? nil : "OpenAI keys start with sk-."
    }
}

final class AIProviderCredentialStore: @unchecked Sendable {
    static let shared = AIProviderCredentialStore()

    private let service: String
    private let inMemory: Bool
    private var memory: [String: String] = [:]
    private let memoryLock = NSLock()

    init(service: String? = nil, inMemory: Bool = false) {
        self.service = service ?? Self.defaultService
        self.inMemory = inMemory
    }

    static var defaultService: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.blakecrosley.captainslog"
        return bundleID + ".ai"
    }

    @discardableResult
    func saveKey(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return saveString(trimmed, account: provider.keychainAccount)
    }

    func loadKey(for provider: AIProvider) -> String? {
        loadString(account: provider.keychainAccount)
    }

    func hasKey(for provider: AIProvider) -> Bool {
        loadKey(for: provider) != nil
    }

    func keyPreview(for provider: AIProvider, visibleSuffixLength: Int = 6) -> String? {
        guard let key = loadKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }

        let suffix = key.suffix(max(1, visibleSuffixLength))
        let prefix = key.hasPrefix("sk-proj-") ? "sk-proj-" : "sk-"
        return "\(prefix)...\(suffix)"
    }

    func deleteKey(for provider: AIProvider) {
        deleteString(account: provider.keychainAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func saveString(_ value: String, account: String) -> Bool {
        if inMemory {
            memoryLock.lock()
            defer { memoryLock.unlock() }
            memory[account] = value
            return true
        }

        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attrs = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private func loadString(account: String) -> String? {
        if inMemory {
            memoryLock.lock()
            defer { memoryLock.unlock() }
            return memory[account]
        }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteString(account: String) {
        if inMemory {
            memoryLock.lock()
            defer { memoryLock.unlock() }
            memory.removeValue(forKey: account)
            return
        }

        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
