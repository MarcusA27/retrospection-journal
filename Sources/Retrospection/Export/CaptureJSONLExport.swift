import Foundation

/// Headless bridge from the encrypted capture store to the Python journal pipeline.
///
/// The desktop-app keystrokes live in the SQLCipher store, which the Python scripts can't read (no
/// SQLCipher driver). This dumps the recent days as plaintext JSONL under the journal's `capture/`
/// dir, where `sources.from_capture` folds them into the daily entry alongside Claude Code. The app
/// binary already holds the key and links SQLCipher, so it does the decryption; nothing else needs to.
///
/// One JSON object per line, one line per entry: {logical_date, app, title?, start_utc, end_utc, text}.
/// Files are written owner-only (0600) since they hold reconstructed keystrokes in the clear.
struct CaptureJSONLExport {
    let store: Store

    /// Canonical export dir, alongside the journal the Look Back GUI and Python scripts already share.
    static func defaultOutDir() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Retrospection/journal/capture", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Writes the most recent `days` logical dates that have entries (allDates is newest-first).
    /// Returns the number of day files written.
    @discardableResult
    func run(outDir: URL, days: Int) throws -> Int {
        var written = 0
        for date in try store.allDates().prefix(days) {
            let entries = try store.entries(for: date)
            guard !entries.isEmpty else { continue }

            var lines: [String] = []
            for e in entries {
                var obj: [String: Any] = [
                    "logical_date": e.logicalDate,
                    "app": e.appName,
                    "start_utc": e.startUTC,
                    "end_utc": e.endUTC,
                    "text": e.text,
                ]
                if let title = e.windowTitle { obj["title"] = title }
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
                lines.append(String(decoding: data, as: UTF8.self))
            }

            let file = outDir.appendingPathComponent("\(date).jsonl")
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            written += 1
        }
        return written
    }
}
