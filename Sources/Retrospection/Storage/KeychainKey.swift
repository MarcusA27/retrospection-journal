import Foundation
import Security

/// Owns the database encryption key. The key is a random 32 bytes, created once and stored in the
/// login Keychain. It never leaves the device and is only ever read into memory to key the database.
enum KeychainKey {
    private static let service = "com.retrospection.journal"
    private static let account = "db-encryption-key-v1"

    enum KeyError: Error, CustomStringConvertible {
        case generationFailed
        case keychainStore(OSStatus)
        case keychainRead(OSStatus)

        var description: String {
            switch self {
            case .generationFailed: return "failed to generate random key"
            case .keychainStore(let s): return "keychain store failed (OSStatus \(s))"
            case .keychainRead(let s): return "keychain read failed (OSStatus \(s))"
            }
        }
    }

    /// Returns the existing key as 64 hex chars, creating and persisting one on first run.
    static func loadOrCreateHexKey() throws -> String {
        if let existing = try read() {
            return existing.hexString
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KeyError.generationFailed
        }
        let data = Data(bytes)
        try store(data)
        return data.hexString
    }

    /// Returns the existing key as 64 hex chars if present, without creating one. Used for migration.
    static func readExistingHexKey() -> String? {
        guard let data = try? read() else { return nil }
        return data.hexString
    }

    /// Generates a fresh random 32-byte key as 64 hex chars (not persisted here).
    static func generateHexKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KeyError.generationFailed
        }
        return Data(bytes).hexString
    }

    private static func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeyError.keychainRead(status)
        }
    }

    private static func store(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Available after first unlock, never migrated off this device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychainStore(status) }
    }

    /// Deletes the key from the Keychain. Used by wipe-all so a wiped database can never be reopened.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
