import Foundation
import AppKit
import ApplicationServices
import IOKit.hid

/// Thin wrappers over the two TCC permissions this app needs:
///   - Input Monitoring  — required for a keyboard CGEventTap on modern macOS.
///   - Accessibility     — required to read focused-window titles via the AX API (segmentation).
/// Both are local, user-granted toggles in System Settings → Privacy & Security.
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts (once) for Accessibility, opening the system dialog that deep-links to Settings.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the Input Monitoring prompt. Returns true if already granted.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Opens the relevant Privacy panes so the user can flip the toggles.
    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
