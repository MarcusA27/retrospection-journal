import AppKit
import ApplicationServices

/// The capture context an entry is segmented by.
struct AppContext: Equatable {
    let bundleID: String?
    let appName: String
    let windowTitle: String?
}

/// Resolves the frontmost application (no permission needed) and its focused window title (needs
/// Accessibility permission; degrades to `nil` without it). Calls are throttled because reading the
/// AX tree on every keystroke is wasteful — within a window the title rarely changes mid-typing.
final class FrontmostContext {
    private var cached: AppContext?
    private var lastSampleNanos: UInt64 = 0
    private let minIntervalNanos: UInt64 = 300_000_000 // 0.3s

    /// Drops the cache so the next `current()` re-samples immediately. Called on app activation,
    /// where the context definitely changed, so keystrokes aren't misattributed during the throttle.
    func invalidate() {
        cached = nil
        lastSampleNanos = 0
    }

    /// Returns the current context, refreshing at most every 0.3s. `force` bypasses the throttle.
    func current(force: Bool = false) -> AppContext {
        let now = DispatchTime.now().uptimeNanoseconds
        if !force, let cached, now &- lastSampleNanos < minIntervalNanos {
            return cached
        }
        lastSampleNanos = now
        let ctx = sample()
        cached = ctx
        return ctx
    }

    private func sample() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppContext(bundleID: nil, appName: "Unknown", windowTitle: nil)
        }
        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let title = focusedWindowTitle(pid: app.processIdentifier)
        return AppContext(bundleID: app.bundleIdentifier, appName: name, windowTitle: title)
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else {
            return nil
        }
        let windowElement = window as! AXUIElement
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else {
            return nil
        }
        return title
    }
}
