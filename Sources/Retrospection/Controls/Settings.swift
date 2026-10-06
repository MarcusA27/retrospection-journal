import Foundation

/// Small persisted preferences. Pause state survives relaunch so an explicit pause is honored
/// until the user resumes.
final class Settings {
    private let defaults: UserDefaults
    private let pausedKey = "capturePaused"
    private let captureOnlyKey = "captureOnlyBundleIDs"
    private let captureOnlySeededKey = "captureOnlySeeded"
    private let captureEnabledKey = "captureEnabled"

    /// Default capture scope: the Claude desktop app only.
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey: captureOnlySeededKey) {
            defaults.set([Settings.claudeBundleID], forKey: captureOnlyKey)
            defaults.set(true, forKey: captureOnlySeededKey)
        }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: pausedKey) }
        set { defaults.set(newValue, forKey: pausedKey) }
    }

    /// Whether keystroke capture runs at all. OFF by default: the journal now sources from Claude Code
    /// transcripts and the data export, not the keylogger, so capture is dormant — and the app asks for
    /// no Input Monitoring / Accessibility permissions — unless explicitly turned on. Set
    /// RETROSPECTION_CAPTURE=1 in the environment, or flip the persisted toggle, to re-enable it.
    var captureEnabled: Bool {
        get {
            if ProcessInfo.processInfo.environment["RETROSPECTION_CAPTURE"] == "1" { return true }
            return defaults.bool(forKey: captureEnabledKey)
        }
        set { defaults.set(newValue, forKey: captureEnabledKey) }
    }

    /// When non-empty, capture is restricted to *only* these bundle ids (allow-list).
    /// Seeded to the Claude app. Empty means "capture everything except the ignore list."
    var captureOnlyBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: captureOnlyKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: captureOnlyKey) }
    }

    /// The early cutoff hour that anchors logical days (default 4am).
    let cutoffHour = 4

    /// Idle gap (seconds) that closes the current entry and re-anchors the day. 4 hours.
    let idleGapSeconds: TimeInterval = 4 * 3600
}
