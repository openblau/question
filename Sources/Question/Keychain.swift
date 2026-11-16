import Foundation
import Security

/// Stores only the API key, encrypted in the user's login Keychain.
/// Conversations are never persisted anywhere.
enum Keychain {
    private static let service = "com.openblau.question"
    private static let account = "anthropic-api-key"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Couldn't save the key to the Keychain: \(reason)"
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]   // never sync to iCloud Keychain
    }

    /// Whether a key is saved. Asks only for attributes, so macOS never shows a password prompt for it.
    static var exists: Bool {
        SecItemCopyMatching(baseQuery as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            // Readable only while the Mac is unlocked; never leaves this device (no backups/migration).
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrLabel as String: "Question — Anthropic API key",
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query = baseQuery.merging(attributes) { $1 }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
