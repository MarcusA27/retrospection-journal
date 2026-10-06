import AppKit

// Headless mode: `--export-capture [days]` dumps the recent capture days to plaintext JSONL for the
// Python journal pipeline, then exits — no menu bar, no event tap, no permissions. Read-only, so it
// runs safely alongside the live menu-bar instance (SQLite WAL allows concurrent readers).
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--export-capture" {
    let days = CommandLine.arguments.count >= 3 ? (Int(CommandLine.arguments[2]) ?? 7) : 7
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Retrospection: \(message)\n".utf8)); exit(1)
    }
    do {
        let store = try Store(url: Store.defaultDatabaseURL(), hexKey: KeyStore.loadOrCreateHexKey())
        let outDir = try CaptureJSONLExport.defaultOutDir()
        let n = try CaptureJSONLExport(store: store).run(outDir: outDir, days: days)
        FileHandle.standardError.write(Data("Retrospection: exported \(n) capture day(s) to \(outDir.path)\n".utf8))
        exit(0)
    } catch {
        fail("capture export failed: \(error)")
    }
}

// Menu-bar (accessory) app. The delegate is held for the process lifetime by this top-level binding.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
