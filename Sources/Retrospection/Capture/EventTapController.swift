import Foundation
import CoreGraphics

/// Owns the system-wide CGEventTap for keyDown events. Listen-only (never modifies or blocks input).
/// The tap is attached to the main run loop; per-keystroke work is light and persistence is handed
/// off to the store queue, so the callback never risks a tap-timeout disable.
///
/// Secure Event Input (password fields in browsers, password managers, terminals) prevents the tap
/// from ever receiving those events. That is by design and respected — we do not try to defeat it.
final class EventTapController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called for each keyDown: (keyCode, produced Unicode string, modifier flags).
    var onKeyDown: ((Int64, String, CGEventFlags) -> Void)?

    var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Attempts to create and enable the tap. Returns false if the OS denied it (missing
    /// Input Monitoring / Accessibility permission) — the caller then prompts the user.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The OS disables a tap that ran too long or after certain input changes — re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        let characters = length > 0 ? String(utf16CodeUnits: buffer, count: length) : ""

        onKeyDown?(keyCode, characters, event.flags)
    }
}
