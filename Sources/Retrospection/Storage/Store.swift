import Foundation

/// High-level persistence. Owns the single `Database` connection and serializes every access
/// through one queue, so the capture path and menu-bar actions never race on the connection.
final class Store {
    private let db: Database
    private let queue = DispatchQueue(label: "com.retrospection.store")

    /// Default on-disk location: ~/Library/Application Support/Retrospection/journal.sqlite
    static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Retrospection", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("journal.sqlite")
    }

    init(url: URL, hexKey: String) throws {
        self.db = try Database(path: url.path, hexKey: hexKey)
        try queue.sync { try migrate() }
    }

    // MARK: - Schema

    /// Versioned via `PRAGMA user_version`. v0 ships the full durable schema, including an (empty)
    /// per-day `distillations` table so distillation and look-back attach later with no migration.
    private func migrate() throws {
        let version = try db.query("PRAGMA user_version;") { $0.int(0) }.first ?? 0
        if version < 1 {
            try db.transaction {
                try db.execute("""
                CREATE TABLE IF NOT EXISTS days (
                    logical_date            TEXT PRIMARY KEY,        -- 'YYYY-MM-DD', cutoff-anchored
                    timezone_identifier     TEXT NOT NULL,
                    timezone_offset_seconds INTEGER NOT NULL,
                    day_start_utc           REAL NOT NULL,
                    day_end_utc             REAL NOT NULL,
                    cutoff_hour             INTEGER NOT NULL DEFAULT 4,
                    created_at              REAL NOT NULL,
                    updated_at              REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS entries (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    logical_date TEXT NOT NULL REFERENCES days(logical_date) ON DELETE CASCADE,
                    app_name     TEXT NOT NULL,
                    window_title TEXT,
                    start_utc    REAL NOT NULL,
                    end_utc      REAL NOT NULL,
                    text         TEXT NOT NULL,
                    created_at   REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_entries_day ON entries(logical_date, start_utc);

                -- Reserved for the nightly distillation. Empty in v0; present so the look-back and
                -- distillation features attach per day without touching the entries schema.
                CREATE TABLE IF NOT EXISTS distillations (
                    logical_date  TEXT PRIMARY KEY REFERENCES days(logical_date) ON DELETE CASCADE,
                    summary       TEXT,
                    model         TEXT,
                    metadata_json TEXT,
                    created_at    REAL,
                    updated_at    REAL
                );
                """)
                try db.execute("PRAGMA user_version = 1;")
            }
        }
    }

    // MARK: - Writes

    /// Inserts a day if absent, or extends its boundary metadata (min start, max end) if present.
    /// Called on every entry checkpoint so a day's span always reflects all of its entries.
    func upsertDay(_ day: Day) throws {
        try queue.sync {
            let now = Date().timeIntervalSince1970
            try db.run("""
                INSERT INTO days (logical_date, timezone_identifier, timezone_offset_seconds,
                                  day_start_utc, day_end_utc, cutoff_hour, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(logical_date) DO UPDATE SET
                    day_start_utc = min(day_start_utc, excluded.day_start_utc),
                    day_end_utc   = max(day_end_utc, excluded.day_end_utc),
                    updated_at    = excluded.updated_at;
                """, [
                    .text(day.logicalDate), .text(day.timezoneIdentifier),
                    .int(Int64(day.timezoneOffsetSeconds)),
                    .double(day.startUTC), .double(day.endUTC),
                    .int(Int64(day.cutoffHour)), .double(now), .double(now)
                ])
        }
    }

    /// Inserts a new entry row and returns its id. The id lets the capture layer keep updating an
    /// in-progress entry in place (durable checkpointing) instead of buffering it only in memory.
    @discardableResult
    func insertEntry(_ entry: Entry) throws -> Int64 {
        try queue.sync {
            let now = Date().timeIntervalSince1970
            return try db.run("""
                INSERT INTO entries (logical_date, app_name, window_title, start_utc, end_utc, text, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """, [
                    .text(entry.logicalDate), .text(entry.appName), SQLValue(entry.windowTitle),
                    .double(entry.startUTC), .double(entry.endUTC), .text(entry.text), .double(now)
                ])
        }
    }

    /// Updates the end time and text of an in-progress entry as the user keeps typing in one context.
    func updateEntry(id: Int64, endUTC: Double, text: String) throws {
        try queue.sync {
            try db.run("UPDATE entries SET end_utc = ?, text = ? WHERE id = ?;",
                       [.double(endUTC), .text(text), .int(id)])
            return
        }
    }

    // MARK: - Reads

    /// Direct keyed lookup of one day's metadata.
    func day(_ logicalDate: String) throws -> Day? {
        try queue.sync {
            try db.query("""
                SELECT logical_date, timezone_identifier, timezone_offset_seconds,
                       day_start_utc, day_end_utc, cutoff_hour
                FROM days WHERE logical_date = ?;
                """, [.text(logicalDate)]) { r in
                Day(
                    logicalDate: r.string(0), timezoneIdentifier: r.string(1),
                    timezoneOffsetSeconds: Int(r.int(2)), startUTC: r.double(3),
                    endUTC: r.double(4), cutoffHour: Int(r.int(5))
                )
            }.first
        }
    }

    /// All entries for a day, in chronological order. Direct keyed lookup on the day, no scan.
    func entries(for logicalDate: String) throws -> [Entry] {
        try queue.sync {
            try db.query("""
                SELECT id, logical_date, app_name, window_title, start_utc, end_utc, text
                FROM entries WHERE logical_date = ? ORDER BY start_utc ASC, id ASC;
                """, [.text(logicalDate)]) { r in
                Entry(
                    id: r.int(0), logicalDate: r.string(1), appName: r.string(2),
                    windowTitle: r.stringOrNil(3), startUTC: r.double(4),
                    endUTC: r.double(5), text: r.string(6)
                )
            }
        }
    }

    /// Logical dates that have at least one day record, newest first.
    func allDates() throws -> [String] {
        try queue.sync {
            try db.query("SELECT logical_date FROM days ORDER BY logical_date DESC;") { $0.string(0) }
        }
    }

    /// Forces WAL contents into the main database file. Used by tests to inspect on-disk bytes;
    /// harmless in production.
    func checkpointWAL() throws {
        try queue.sync { try db.execute("PRAGMA wal_checkpoint(TRUNCATE);") }
    }

    // MARK: - Wipe

    /// Irreversibly deletes all captured data. Entries cascade from days; distillations too.
    func wipeAll() throws {
        try queue.sync {
            try db.transaction {
                try db.execute("DELETE FROM entries;")
                try db.execute("DELETE FROM distillations;")
                try db.execute("DELETE FROM days;")
            }
            try db.execute("VACUUM;")
        }
    }
}
