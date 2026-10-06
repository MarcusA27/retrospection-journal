import AppKit
import UniformTypeIdentifiers

/// Menu-bar controller and app lifecycle. Owns the store and capture coordinator, builds the status
/// menu, and routes the user controls: pause/resume, export, ignore-list, wipe.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var store: Store!
    private var coordinator: CaptureCoordinator!
    private var exporter: Exporter!
    private let ignoreList = IgnoreList()
    private let settings = Settings()
    private let lookBack = LookBackWindowController()

    private var statusLabelItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private let datesMenu = NSMenu(title: "Export Day")
    private let ignoreMenu = NSMenu(title: "Ignore List")
    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        // Capture (the keylogger) is opt-in. Off by default, the app is a pure reading surface: it opens
        // the encrypted capture store, starts no event tap, and requests no permissions.
        if settings.captureEnabled {
            do {
                let key = try KeyStore.loadOrCreateHexKey()
                let url = try Store.defaultDatabaseURL()
                store = try Store(url: url, hexKey: key)
            } catch {
                fatalAlert("Could not open the encrypted journal.\n\n\(error)")
                NSApp.terminate(nil)
                return
            }
            coordinator = CaptureCoordinator(store: store, ignoreList: ignoreList, settings: settings)
            exporter = Exporter(store: store)
        }

        buildStatusItem()

        if settings.captureEnabled {
            promptForPermissionsIfNeeded()
            if !settings.isPaused {
                coordinator.start()
            }
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
            refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    // MARK: - Status item & menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        let lookBackItem = NSMenuItem(title: "Look Back…", action: #selector(openLookBack), keyEquivalent: "l")
        lookBackItem.target = self

        if settings.captureEnabled {
            statusLabelItem = NSMenuItem(title: "Capturing", action: nil, keyEquivalent: "")
            statusLabelItem.isEnabled = false
            menu.addItem(statusLabelItem)

            permissionItem = NSMenuItem(title: "Grant Permissions…", action: #selector(openPermissions), keyEquivalent: "")
            permissionItem.target = self
            permissionItem.isHidden = true
            menu.addItem(permissionItem)

            menu.addItem(.separator())
            menu.addItem(lookBackItem)
            menu.addItem(.separator())

            pauseItem = NSMenuItem(title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)

            menu.addItem(.separator())

            let exportItem = NSMenuItem(title: "Export Day", action: nil, keyEquivalent: "")
            datesMenu.delegate = self
            exportItem.submenu = datesMenu
            menu.addItem(exportItem)

            let ignoreItem = NSMenuItem(title: "Ignore List", action: nil, keyEquivalent: "")
            ignoreMenu.delegate = self
            ignoreItem.submenu = ignoreMenu
            menu.addItem(ignoreItem)

            menu.addItem(.separator())

            let wipeItem = NSMenuItem(title: "Wipe All Data…", action: #selector(wipeAll), keyEquivalent: "")
            wipeItem.target = self
            menu.addItem(wipeItem)
        } else {
            // Reading-only mode: no capture, no permissions, just the journal.
            menu.addItem(lookBackItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Retrospection", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let button = statusItem.button {
            let symbol = settings.captureEnabled ? "circle.inset.filled" : "book.closed"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Retrospection")
            button.image?.isTemplate = true
            if button.image == nil { button.title = "R" }
        }
    }

    /// Refreshes the status icon, labels, and (re)starts capture once permissions appear.
    private func refresh() {
        guard settings.captureEnabled else { return }
        let permitted = Permissions.hasInputMonitoring
        let paused = settings.isPaused

        if !paused, permitted, !coordinator.isCapturing {
            coordinator.start()
        }

        let symbol: String
        let status: String
        if !permitted {
            symbol = "exclamationmark.triangle"
            status = "Needs Input Monitoring permission"
        } else if paused {
            symbol = "pause.circle"
            status = "Paused"
        } else {
            symbol = "circle.inset.filled"
            status = "Capturing\(captureScopeSuffix())"
        }

        statusLabelItem.title = status
        pauseItem.title = paused ? "Resume Capture" : "Pause Capture"
        permissionItem.isHidden = permitted

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: status)
            button.image?.isTemplate = true
            if button.image == nil { button.title = "R" }
        }
    }

    /// Describes the capture scope for the status line, e.g. " — Claude only".
    private func captureScopeSuffix() -> String {
        let only = settings.captureOnlyBundleIDs
        guard !only.isEmpty else { return "" }
        if only == [Settings.claudeBundleID] { return " — Claude only" }
        return " — \(only.count) apps only"
    }

    // MARK: - Permissions

    private func promptForPermissionsIfNeeded() {
        let needsInput = !Permissions.hasInputMonitoring
        let needsAX = !Permissions.hasAccessibility
        guard needsInput || needsAX else { return }

        // Register the app in the TCC lists (triggers the system prompts).
        Permissions.requestInputMonitoring()
        Permissions.requestAccessibility()

        let alert = NSAlert()
        alert.messageText = "Retrospection needs permission to capture"
        alert.informativeText = """
        Capture requires Input Monitoring. Window titles (used to label entries) require Accessibility.

        Enable Retrospection in System Settings → Privacy & Security, then capture starts automatically.
        Everything stays on this Mac — nothing is ever sent anywhere.
        """
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: Permissions.openInputMonitoringSettings()
        case .alertSecondButtonReturn: Permissions.openAccessibilitySettings()
        default: break
        }
    }

    @objc private func openPermissions() {
        Permissions.openInputMonitoringSettings()
    }

    @objc private func openLookBack() {
        lookBack.show()
    }

    // MARK: - Actions

    @objc private func togglePause() {
        settings.isPaused.toggle()
        if settings.isPaused {
            coordinator.stop()
        } else if Permissions.hasInputMonitoring {
            coordinator.start()
        }
        refresh()
    }

    @objc private func exportDate(_ sender: NSMenuItem) {
        guard let date = sender.representedObject as? String else { return }
        coordinator.flush()   // persist the in-progress entry so the export is complete to the last keystroke
        do {
            guard let text = try exporter.exportText(for: date) else {
                infoAlert("No entries captured for \(date).")
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Retrospection-\(date).txt"
            panel.allowedContentTypes = [.plainText]
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            infoAlert("Export failed:\n\(error)")
        }
    }

    @objc private func toggleIgnore(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        ignoreList.toggle(bundleID)
    }

    @objc private func wipeAll() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Wipe all captured data?"
        alert.informativeText = "This permanently deletes every day and entry. This cannot be undone."
        alert.addButton(withTitle: "Wipe Everything")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        coordinator.discardCurrent()
        do {
            try store.wipeAll()
        } catch {
            infoAlert("Wipe failed:\n\(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate (dynamic submenus)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === datesMenu { rebuildDatesMenu() }
        else if menu === ignoreMenu { rebuildIgnoreMenu() }
    }

    private func rebuildDatesMenu() {
        datesMenu.removeAllItems()
        let today = DayBoundary(cutoffHour: settings.cutoffHour).logicalDate(for: Date())
        let dates = ((try? store.allDates()) ?? [])
        if dates.isEmpty {
            let item = NSMenuItem(title: "No days captured yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            datesMenu.addItem(item)
            return
        }
        for date in dates {
            let label = date == today ? "\(date) (today)" : date
            let item = NSMenuItem(title: label, action: #selector(exportDate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = date
            datesMenu.addItem(item)
        }
    }

    private func rebuildIgnoreMenu() {
        ignoreMenu.removeAllItems()

        let header = NSMenuItem(title: "Never capture (check to ignore):", action: nil, keyEquivalent: "")
        header.isEnabled = false
        ignoreMenu.addItem(header)
        ignoreMenu.addItem(.separator())

        let ignored = ignoreList.bundleIDs()

        // Currently running, user-facing apps.
        var shown = Set<String>()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in running {
            guard let bundleID = app.bundleIdentifier else { continue }
            shown.insert(bundleID)
            addIgnoreItem(name: app.localizedName ?? bundleID, bundleID: bundleID, ignored: ignored.contains(bundleID))
        }

        // Ignored apps that aren't currently running, so the list can still be edited.
        let offline = ignored.subtracting(shown).sorted()
        if !offline.isEmpty {
            ignoreMenu.addItem(.separator())
            for bundleID in offline {
                addIgnoreItem(name: bundleID, bundleID: bundleID, ignored: true)
            }
        }
    }

    private func addIgnoreItem(name: String, bundleID: String, ignored: Bool) {
        let item = NSMenuItem(title: name, action: #selector(toggleIgnore(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = bundleID
        item.state = ignored ? .on : .off
        ignoreMenu.addItem(item)
    }

    // MARK: - Alerts

    private func infoAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Retrospection"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func fatalAlert(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Retrospection"
        alert.informativeText = text
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }
}
