import XCTest
@testable import Retrospection

final class StorageTests: XCTestCase {
    private var dir: URL!
    private var dbURL: URL!
    private let key = String(repeating: "ab", count: 32)        // 64 hex chars = 32 bytes
    private let otherKey = String(repeating: "cd", count: 32)

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("retro-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("journal.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeDay(_ logicalDate: String, start: Double, end: Double) -> Day {
        Day(logicalDate: logicalDate, timezoneIdentifier: "America/New_York",
            timezoneOffsetSeconds: -4 * 3600, startUTC: start, endUTC: end, cutoffHour: 4)
    }

    func testRoundTripAndDayUpsert() throws {
        let store = try Store(url: dbURL, hexKey: key)
        let t0 = 1_000_000.0
        let day = makeDay("2026-06-11", start: t0, end: t0 + 60)

        try store.upsertDay(day)
        let id = try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Notes",
                                             windowTitle: "Journal", startUTC: t0, endUTC: t0 + 60,
                                             text: "first thoughts"))
        try store.updateEntry(id: id, endUTC: t0 + 120, text: "first thoughts, revised")

        // A second entry in a different context, later in the same day — extends the day's end.
        try store.upsertDay(makeDay("2026-06-11", start: t0 + 200, end: t0 + 260))
        try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Safari",
                                    windowTitle: "Research", startUTC: t0 + 200, endUTC: t0 + 260,
                                    text: "looked something up"))

        let entries = try store.entries(for: "2026-06-11")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "first thoughts, revised")
        XCTAssertEqual(entries[0].endUTC, t0 + 120)
        XCTAssertEqual(entries[1].appName, "Safari")

        let stored = try XCTUnwrap(try store.day("2026-06-11"))
        XCTAssertEqual(stored.startUTC, t0)            // min across entries
        XCTAssertEqual(stored.endUTC, t0 + 260)        // max across entries
        XCTAssertEqual(try store.allDates(), ["2026-06-11"])
    }

    func testWipeRemovesEverything() throws {
        let store = try Store(url: dbURL, hexKey: key)
        try store.upsertDay(makeDay("2026-06-11", start: 1, end: 2))
        try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Notes",
                                    windowTitle: nil, startUTC: 1, endUTC: 2, text: "x"))
        try store.wipeAll()
        XCTAssertEqual(try store.allDates(), [])
        XCTAssertTrue(try store.entries(for: "2026-06-11").isEmpty)
    }

    func testWrongKeyIsRejected() throws {
        do { _ = try Store(url: dbURL, hexKey: key) }       // create keyed db
        XCTAssertThrowsError(try Store(url: dbURL, hexKey: otherKey)) { error in
            guard case DatabaseError.key = error else {
                return XCTFail("expected .key, got \(error)")
            }
        }
    }

    func testFileIsEncryptedAtRest() throws {
        let store = try Store(url: dbURL, hexKey: key)
        try store.upsertDay(makeDay("2026-06-11", start: 1, end: 2))
        try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Notes",
                                    windowTitle: nil, startUTC: 1, endUTC: 2,
                                    text: "UNIQUE_SECRET_NEEDLE_42"))
        // Force WAL contents into the main database file before inspecting bytes.
        try store.checkpointWAL()

        let raw = try Data(contentsOf: dbURL)
        // Plaintext must not appear, and the standard SQLite header must be absent (encrypted header).
        XCTAssertFalse(raw.range(of: Data("UNIQUE_SECRET_NEEDLE_42".utf8)) != nil,
                       "plaintext found on disk — database is not encrypted")
        let sqliteMagic = Data("SQLite format 3".utf8)
        XCTAssertNil(raw.range(of: sqliteMagic), "unencrypted SQLite header present")
    }

    func testExportRendersGroupedDocument() throws {
        let store = try Store(url: dbURL, hexKey: key)
        let t0 = 1_700_000_000.0
        try store.upsertDay(makeDay("2026-06-11", start: t0, end: t0 + 600))
        try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Notes",
                                    windowTitle: "Journal", startUTC: t0, endUTC: t0 + 60, text: "morning pages"))
        try store.insertEntry(Entry(id: nil, logicalDate: "2026-06-11", appName: "Notes",
                                    windowTitle: "Todo", startUTC: t0 + 120, endUTC: t0 + 180, text: "ship v0"))

        let text = try XCTUnwrap(Exporter(store: store).exportText(for: "2026-06-11"))
        XCTAssertTrue(text.contains("Retrospection — 2026-06-11 (America/New_York)"))
        XCTAssertTrue(text.contains("## Notes"))
        XCTAssertTrue(text.contains("morning pages"))
        XCTAssertTrue(text.contains("ship v0"))
        XCTAssertNil(try Exporter(store: store).exportText(for: "2099-01-01"))   // no data
    }
}
