import Foundation
import AppKit
import CoreGraphics

/// The capture brain: turns the keystroke stream into segmented, day-bucketed entries and persists
/// them. Runs entirely on the main run loop (where the event tap delivers), so its mutable state
/// needs no locking. Persistence is small and synchronous via the store's own serial queue.
///
/// Segmentation: one entry per (app, window title) context. An entry stays open and accumulates
/// text while that context is frontmost, is checkpointed to disk periodically (crash-durable), and
/// is finalized when the context changes, a long idle gap occurs, capture pauses, or the app quits.
final class CaptureCoordinator {
    private let store: Store
    private let ignoreList: IgnoreList
    private let settings: Settings
    private let frontmost = FrontmostContext()
    private let tap = EventTapController()
    private let reconstructor = TextReconstructor()

    // Open-entry state (main-thread only).
    private var context: AppContext?
    private var startUTC: Double = 0
    private var lastActivityUTC: Double = 0
    private var logicalDate: String = ""
    private var openEntryID: Int64?

    private var checkpointTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    private(set) var isCapturing = false

    init(store: Store, ignoreList: IgnoreList, settings: Settings) {
        self.store = store
        self.ignoreList = ignoreList
        self.settings = settings
        tap.onKeyDown = { [weak self] keyCode, characters, flags in
            self?.onKeyDown(keyCode: keyCode, characters: characters, flags: flags)
        }
    }

    private var dayBoundary: DayBoundary {
        DayBoundary(cutoffHour: settings.cutoffHour, timeZone: .current)
    }

    // MARK: - Lifecycle

    /// Starts the event tap. Returns false if the OS denied it (permissions not yet granted).
    @discardableResult
    func start() -> Bool {
        guard !isCapturing else { return true }
        guard tap.start() else { return false }
        isCapturing = true
        // Periodic durability checkpoint of the open entry.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkpoint(final: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer
        // On app switch, drop the cached context so the next keystroke segments under the new app.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.frontmost.invalidate()
        }
        return true
    }

    /// Stops capture, finalizing any open entry. Used by pause and on quit.
    func stop() {
        guard isCapturing else { return }
        finalizeCurrent()
        tap.stop()
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        isCapturing = false
    }

    /// Discards the in-memory open entry without persisting (used around a wipe).
    func discardCurrent() {
        clearCurrent()
    }

    /// Writes the in-progress entry to disk without closing it, so a read (e.g. export) sees text
    /// right up to the last keystroke instead of the last 30s checkpoint.
    func flush() {
        checkpoint(final: false)
    }

    // MARK: - Keystroke handling

    private func onKeyDown(keyCode: Int64, characters: String, flags: CGEventFlags) {
        let now = Date()
        let nowUTC = now.timeIntervalSince1970
        let ctx = frontmost.current()

        // Capture only in-scope apps (v0: the Claude app only); close out anything in progress.
        let scope = CaptureScope(allowOnly: settings.captureOnlyBundleIDs, ignore: ignoreList.bundleIDs())
        if !scope.shouldCapture(bundleID: ctx.bundleID) {
            finalizeCurrent()
            return
        }

        // A long idle gap closes the current entry (and, with the cutoff, re-anchors the day).
        if context != nil, nowUTC - lastActivityUTC >= settings.idleGapSeconds {
            finalizeCurrent()
        }

        let day = dayBoundary.logicalDate(for: now)
        // New entry whenever there is none, the context changed, or we crossed the day cutoff.
        if context == nil || context != ctx || day != logicalDate {
            finalizeCurrent()
            beginEntry(context: ctx, now: nowUTC, logicalDate: day)
        }

        reconstructor.apply(keyCode: keyCode, characters: characters, flags: flags)
        lastActivityUTC = nowUTC
    }

    private func beginEntry(context: AppContext, now: Double, logicalDate: String) {
        self.context = context
        self.startUTC = now
        self.lastActivityUTC = now
        self.logicalDate = logicalDate
        self.openEntryID = nil
        reconstructor.reset()
    }

    // MARK: - Persistence

    /// Writes the open entry to disk. `final` clears the in-memory state afterward.
    private func checkpoint(final: Bool) {
        guard let context else { return }
        guard !reconstructor.isEmpty else {
            if final { clearCurrent() }
            return
        }
        let text = reconstructor.finalText()
        guard !text.isEmpty else {
            if final { clearCurrent() }
            return
        }

        let startDate = Date(timeIntervalSince1970: startUTC)
        let day = dayBoundary.makeDay(for: startDate, start: startUTC, end: lastActivityUTC)
        do {
            try store.upsertDay(day)
            if let id = openEntryID {
                try store.updateEntry(id: id, endUTC: lastActivityUTC, text: text)
            } else {
                let entry = Entry(
                    id: nil, logicalDate: logicalDate, appName: context.appName,
                    windowTitle: context.windowTitle, startUTC: startUTC,
                    endUTC: lastActivityUTC, text: text
                )
                openEntryID = try store.insertEntry(entry)
            }
        } catch {
            FileHandle.standardError.write(Data("Retrospection: persist failed: \(error)\n".utf8))
        }
        if final { clearCurrent() }
    }

    private func finalizeCurrent() {
        checkpoint(final: true)
    }

    private func clearCurrent() {
        context = nil
        startUTC = 0
        lastActivityUTC = 0
        logicalDate = ""
        openEntryID = nil
        reconstructor.reset()
    }
}
