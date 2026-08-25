import Foundation
import Security

public enum KeychainError: Error, Equatable {
    /// The system asked for permission to release the secret and did not get an
    /// answer. Its own case because the fix is a click, not a reinstall.
    case userCancelled
    case failed(OSStatus)

    static func from(_ status: OSStatus) -> KeychainError {
        status == errSecUserCanceled ? .userCancelled : .failed(status)
    }
}

/// The API key, in the login Keychain and nowhere else.
///
/// Never a plist, never an environment variable, never the repo. A generic
/// password item is the only storage on this machine that survives a rebuild
/// and is not readable by anything that can read the app bundle.
public struct APIKeyStore: Sendable {

    public static let service = "com.knapiontek.kibitz"

    private let account: String

    public init(account: String = "deepseek") {
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
    }

    /// Whether a key is stored, answered from the item's attributes.
    ///
    /// Deliberately does not read the secret. A Keychain ACL guards the data,
    /// not the metadata, and macOS rebuilds the ACL against the exact binary
    /// that created the item - so every rebuild of the app turns a read into a
    /// system prompt. Greying out a menu item is not worth one.
    public func exists() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// `nil` when no key has been set, which is a normal state: the app works
    /// on the subscription backend without one.
    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.from(status)
        }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    public func save(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.from(status) }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        // The app can be a login item, so it may run before the Keychain is
        // unlocked interactively. AfterFirstUnlock keeps the first check of the
        // day from stalling on a prompt.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.from(added) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.from(status)
        }
    }
}
