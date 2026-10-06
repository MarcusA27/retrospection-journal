import Foundation

/// A logical day — the primary, addressable unit of the whole product. Keyed by `logicalDate`
/// (a `YYYY-MM-DD` string), it is a direct lookup, never a timestamp scan. Boundary metadata is
/// stored so a day is never ambiguous across timezone changes or DST.
struct Day {
    /// `YYYY-MM-DD` in the capture timezone, anchored to the early cutoff (see `DayBoundary`).
    let logicalDate: String
    /// IANA identifier, e.g. "America/New_York", captured at the day's first activity.
    let timezoneIdentifier: String
    /// UTC offset in seconds at the day's start — lets a day be reconstructed exactly later.
    let timezoneOffsetSeconds: Int
    /// First and last activity instants observed for this day (unix seconds, UTC).
    let startUTC: Double
    let endUTC: Double
    /// The early-cutoff hour used to bucket this day (4 by default). Stored for auditability.
    let cutoffHour: Int
}

/// A single segment of capture under one (app, window) context.
struct Entry {
    var id: Int64?
    let logicalDate: String
    let appName: String
    let windowTitle: String?
    let startUTC: Double
    let endUTC: Double
    let text: String
}
