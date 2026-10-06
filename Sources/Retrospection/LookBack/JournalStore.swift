import Foundation

/// One generated day entry, read from the journal directory.
struct JournalDay: Identifiable, Hashable {
    let date: String       // YYYY-MM-DD (the logical date / filename stem)
    let subject: String?   // one-line summary, from the entry's `# ...` heading
    let body: String       // markdown, heading line stripped
    var id: String { date }
}

/// One generated over-time mirror covering a date range.
struct JournalMirror: Identifiable, Hashable {
    let start: String
    let end: String
    let subject: String?   // one-line essence of the week, from the mirror's `# ...` heading
    let body: String
    var id: String { "\(start)_\(end)" }
    func covers(_ date: String) -> Bool { date >= start && date <= end }
}

/// Reads the entries the generation pipeline writes. Same location the Python scripts target:
/// ~/Library/Application Support/Retrospection/journal/{daily,mirrors}.
enum JournalStore {
    static func journalDirectory() -> URL {
        // Demo/screenshot override: point the app at a separate fake journal so real entries are never
        // loaded. Set RETROSPECTION_JOURNAL_DIR to a directory containing daily/, mirrors/, sentiment.json.
        if let override = ProcessInfo.processInfo.environment["RETROSPECTION_JOURNAL_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Retrospection/journal", isDirectory: true)
    }

    static func loadDays() -> [JournalDay] {
        let dir = journalDirectory().appendingPathComponent("daily", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.compactMap { f in
            guard let raw = try? String(contentsOf: f, encoding: .utf8) else { return nil }
            let (subject, body) = splitHeading(raw)
            return JournalDay(date: f.deletingPathExtension().lastPathComponent, subject: subject, body: body)
        }.sorted { $0.date > $1.date }
    }

    static func loadMirrors() -> [JournalMirror] {
        let dir = journalDirectory().appendingPathComponent("mirrors", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.compactMap { f -> JournalMirror? in
            // filename: mirror-<start>_<end>.md
            let stem = f.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "mirror-", with: "")
            let parts = stem.components(separatedBy: "_")
            guard parts.count == 2, let raw = try? String(contentsOf: f, encoding: .utf8) else { return nil }
            let (subject, body) = splitHeading(raw)
            return JournalMirror(start: parts[0], end: parts[1], subject: subject, body: body)
        }.sorted { $0.start > $1.start }
    }

    /// Splits a leading `# ...` heading off as the subject; returns (subject, body).
    private static func splitHeading(_ raw: String) -> (String?, String) {
        var lines = raw.components(separatedBy: "\n")
        var subject: String?
        if lines.first?.hasPrefix("# ") == true {
            subject = String(lines.removeFirst().dropFirst(2)).trimmingCharacters(in: .whitespaces)
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        }
        return (subject, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
