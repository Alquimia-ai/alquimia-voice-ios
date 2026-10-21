import Foundation
import Security

/// Minimal generic-password wrapper. Works on the Simulator without entitlements.
struct Keychain: Sendable {
    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    let service: String

    func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Passing `nil` or an empty string deletes the item.
    func set(_ value: String?, for account: String) throws {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            for (key, value) in attributes { insert[key] = value }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
