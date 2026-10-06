import Foundation

/// Stores the database encryption key as an owner-only file (chmod 600) in the app's Application
/// Support folder, migrating it out of the Keychain on first run.
///
/// Why not the Keychain: its per-app access prompt is keyed to the app's code signature, so it
/// re-appears on every rebuild (each rebuild is a new signature). A file avoids the prompt entirely.
/// The key never leaves the machine and the file is readable only by the user's account; the journal
/// itself stays SQLCipher-encrypted.
enum KeyStore {
    private static func keyURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Retrospection", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dbkey")
    }

    /// Returns the key, in priority: existing file → migrated Keychain key → freshly generated.
    static func loadOrCreateHexKey() throws -> String {
        let url = try keyURL()
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           existing.count == 64 {
            return existing
        }
        // First run on this version: reuse the existing Keychain key (one final prompt) so the
        // already-encrypted database still opens; otherwise start fresh.
        let hex: String
        if let migrated = KeychainKey.readExistingHexKey() {
            hex = migrated
        } else {
            hex = try KeychainKey.generateHexKey()
        }
        try Data(hex.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return hex
    }
}
