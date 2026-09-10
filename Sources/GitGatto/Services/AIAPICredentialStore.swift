import Foundation
import Security
import LocalAuthentication

enum AIAPICredentialStore {
    private static let service = "dev.gitgatto.client.agent-api"

    private static func query(_ configuration: AIAPIConfiguration) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: configuration.credentialAccount]
    }

    static func contains(_ configuration: AIAPIConfiguration) -> Bool {
        var query = query(configuration)
        query[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ configuration: AIAPIConfiguration) throws -> String? {
        var query = query(configuration)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw AIAPIError.credentialStore }
        return key
    }

    static func save(_ key: String, for configuration: AIAPIConfiguration) throws {
        try configuration.validate()
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else {
            throw AIAPIError.invalidConfiguration
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query(configuration) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(configuration)
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AIAPIError.credentialStore }
        } else if status != errSecSuccess {
            throw AIAPIError.credentialStore
        }
    }

    static func delete(_ configuration: AIAPIConfiguration) throws {
        let status = SecItemDelete(query(configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIAPIError.credentialStore }
    }
}
