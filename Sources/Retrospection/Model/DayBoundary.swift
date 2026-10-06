import Foundation

/// Computes which logical day an instant belongs to.
///
/// Design (the expensive-to-change part, fixed now):
///   - `logicalDate` is a `YYYY-MM-DD` string and is the primary key of a day. There is exactly
///     one day per date — a day is a direct keyed lookup, never a timestamp scan.
///   - The boundary is NOT strict midnight. A day runs from the early cutoff (default 4am) to the
///     next day's cutoff, so a late-night session (e.g. work until 2am) stays in the evening's day.
///   - Concretely: subtract the cutoff hour from local wall time, then take the calendar date.
///     2am with a 4am cutoff maps back to the previous date; 5am maps to the new date.
///   - The "4+ hour idle gap" rule is handled by the caller as a session-close + re-anchor signal
///     (see `CaptureCoordinator`). It never mints a second day for the same calendar date — that
///     would collide with the primary key and break addressability. After a long idle gap the
///     cutoff function naturally advances the date once real time has moved past the next cutoff.
struct DayBoundary {
    let cutoffHour: Int
    let timeZone: TimeZone

    init(cutoffHour: Int = 4, timeZone: TimeZone = .current) {
        self.cutoffHour = cutoffHour
        self.timeZone = timeZone
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// The logical date string for an instant.
    func logicalDate(for date: Date) -> String {
        let shifted = date.addingTimeInterval(TimeInterval(-cutoffHour * 3600))
        let comps = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Builds the day record metadata for an instant (offset/identifier captured at this moment).
    func makeDay(for date: Date, start: Double, end: Double) -> Day {
        Day(
            logicalDate: logicalDate(for: date),
            timezoneIdentifier: timeZone.identifier,
            timezoneOffsetSeconds: timeZone.secondsFromGMT(for: date),
            startUTC: start,
            endUTC: end,
            cutoffHour: cutoffHour
        )
    }
}
