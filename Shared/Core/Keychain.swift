import Foundation
import Security

/// Minimal Keychain wrapper.
/// - `shared: true` stores the item in the App Group access group so the
///   broadcast extension can read it (used for the scoped device token).
/// - `shared: false` keeps it private to the main app (used for auth sessions).
enum Keychain {
    enum Key: String {
        case deviceToken = "device-token"
        case authSession = "auth-session"
    }

    private static let service = "doomscore"

    private static func baseQuery(_ key: Key, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if shared { query[kSecAttrAccessGroup as String] = AppEnvironment.appGroupID }
        return query
    }

    @discardableResult
    static func set(_ data: Data, for key: Key, shared: Bool) -> Bool {
        let query = baseQuery(key, shared: shared)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Readable by extensions once the device has been unlocked after boot;
            // never synced to iCloud or restored to another device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func data(for key: Key, shared: Bool) -> Data? {
        var query = baseQuery(key, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func remove(_ key: Key, shared: Bool) {
        SecItemDelete(baseQuery(key, shared: shared) as CFDictionary)
    }

    @discardableResult
    static func setString(_ value: String, for key: Key, shared: Bool) -> Bool {
        set(Data(value.utf8), for: key, shared: shared)
    }

    static func string(for key: Key, shared: Bool) -> String? {
        data(for: key, shared: shared).flatMap { String(data: $0, encoding: .utf8) }
    }
}
