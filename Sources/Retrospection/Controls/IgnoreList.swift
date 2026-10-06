import Foundation

/// Apps that are never captured, identified by bundle identifier. Backed by UserDefaults and seeded
/// on first run with the obvious sensitive apps (password managers, terminals). When the frontmost
/// app is on this list, capture is suppressed and any in-progress entry is flushed.
final class IgnoreList {
    private let defaults: UserDefaults
    private let listKey = "ignoreListBundleIDs"
    private let seededKey = "ignoreListSeeded"

    /// Reasonable defaults. Note: terminals and password managers also trigger macOS Secure Event
    /// Input, which already blocks capture during password entry — this list makes the intent explicit
    /// and covers the whole app, not just secure fields.
    static let seedDefaults: [String] = [
        "com.apple.Passwords",            // Passwords.app
        "com.apple.keychainaccess",       // Keychain Access
        "com.1password.1password",        // 1Password 8
        "com.agilebits.onepassword7",     // 1Password 7
        "com.bitwarden.desktop",          // Bitwarden
        "com.dashlane.Dashlane",          // Dashlane
        "in.sinew.Enpass-Desktop",        // Enpass
        "com.apple.Terminal",             // Terminal
        "com.googlecode.iterm2",          // iTerm2
        "com.mitchellh.ghostty",          // Ghostty
        "dev.warp.Warp-Stable",           // Warp
        "net.kovidgoyal.kitty",           // kitty
        "org.alacritty"                   // Alacritty
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey: seededKey) {
            defaults.set(IgnoreList.seedDefaults, forKey: listKey)
            defaults.set(true, forKey: seededKey)
        }
    }

    func bundleIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: listKey) ?? [])
    }

    func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs().contains(bundleID)
    }

    func toggle(_ bundleID: String) {
        var ids = bundleIDs()
        if ids.contains(bundleID) { ids.remove(bundleID) } else { ids.insert(bundleID) }
        defaults.set(Array(ids).sorted(), forKey: listKey)
    }
}
