import Foundation
import SQLCipher

/// A value that can cross the SQLite boundary.
enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    init(_ v: Int64) { self = .int(v) }
    init(_ v: Int) { self = .int(Int64(v)) }
    init(_ v: Double) { self = .double(v) }
    init(_ v: String?) { self = v.map { .text($0) } ?? .null }
}

enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case key
    case sql(String, code: Int32)

    var description: String {
        switch self {
        case .open(let m): return "sqlite open failed: \(m)"
        case .key: return "sqlite key rejected (wrong key or corrupt database)"
        case .sql(let m, let c): return "sqlite error (\(c)): \(m)"
        }
    }
}

// SQLite wants the bound-text destructor to copy the bytes; the system header exposes this as a macro.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal, synchronous wrapper over the SQLCipher C API. Not thread-safe by itself;
/// `Store` owns a single instance and serializes all access through one queue.
final class Database {
    private var handle: OpaquePointer?

    /// Opens (creating if needed) an encrypted database at `path`, keyed with a raw 32-byte key
    /// supplied as 64 hex characters. The raw-key form (`x'...'`) skips PBKDF2 — the key is used
    /// directly — which is correct here because the key is already high-entropy random from the Keychain.
    init(path: String, hexKey: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, handle != nil else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw DatabaseError.open(msg)
        }
        // Key must be applied before any other statement touches the database pages.
        try execute("PRAGMA key = \"x'\(hexKey)'\";")
        // Touching sqlite_master forces SQLCipher to decrypt the header — fails fast on a wrong key.
        do {
            try execute("SELECT count(*) FROM sqlite_master;")
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.key
        }
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
    }

    deinit { close() }

    func close() {
        if let h = handle {
            sqlite3_close(h)
            handle = nil
        }
    }

    /// Runs one or more statements with no result rows (DDL, PRAGMA, simple writes).
    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.sql(msg, code: sqlite3_errcode(handle))
        }
    }

    /// Prepares, binds, and runs a write, returning `lastInsertRowID`.
    @discardableResult
    func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        let stmt = try Statement(handle: handle, sql: sql)
        defer { stmt.finalize() }
        try stmt.bind(params)
        try stmt.stepDone()
        return sqlite3_last_insert_rowid(handle)
    }

    /// Prepares, binds, and reads all rows, mapping each with `row`.
    func query<T>(_ sql: String, _ params: [SQLValue] = [], _ row: (Row) throws -> T) throws -> [T] {
        let stmt = try Statement(handle: handle, sql: sql)
        defer { stmt.finalize() }
        try stmt.bind(params)
        var out: [T] = []
        while try stmt.stepRow() {
            out.append(try row(Row(stmt)))
        }
        return out
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}

/// A prepared statement plus its handle, scoped to one query.
final class Statement {
    fileprivate let stmt: OpaquePointer
    private let dbHandle: OpaquePointer?

    init(handle: OpaquePointer?, sql: String) throws {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK, let s else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.sql(msg, code: sqlite3_errcode(handle))
        }
        self.stmt = s
        self.dbHandle = handle
    }

    func bind(_ params: [SQLValue]) throws {
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch value {
            case .int(let v): rc = sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v): rc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .null: rc = sqlite3_bind_null(stmt, idx)
            }
            if rc != SQLITE_OK {
                throw DatabaseError.sql(String(cString: sqlite3_errmsg(dbHandle)), code: rc)
            }
        }
    }

    /// Steps a statement expected to return no rows.
    func stepDone() throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw DatabaseError.sql(String(cString: sqlite3_errmsg(dbHandle)), code: rc)
        }
    }

    /// Steps once; returns true if a row is available, false at end.
    func stepRow() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw DatabaseError.sql(String(cString: sqlite3_errmsg(dbHandle)), code: rc)
    }

    func finalize() { sqlite3_finalize(stmt) }
}

/// Column accessors for the current row of a stepped statement.
struct Row {
    private let stmt: OpaquePointer
    init(_ s: Statement) { self.stmt = s.stmt }

    func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    func string(_ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }
    func stringOrNil(_ i: Int32) -> String? {
        guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
}
