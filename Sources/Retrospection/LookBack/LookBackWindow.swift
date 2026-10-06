import AppKit
import SwiftUI

/// Hosts the SwiftUI look-back window. The app is a menu-bar (accessory) app, so the window is
/// created on demand and brought to front explicitly.
final class LookBackWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Look Back"
            w.center()
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.managed, .fullScreenPrimary]
            w.contentView = NSHostingView(rootView: LookBackView())
            w.setFrameAutosaveName("LookBackWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
