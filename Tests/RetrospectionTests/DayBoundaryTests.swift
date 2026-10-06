import XCTest
@testable import Retrospection

final class DayBoundaryTests: XCTestCase {
    private let tz = TimeZone(identifier: "America/New_York")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }

    private var boundary: DayBoundary { DayBoundary(cutoffHour: 4, timeZone: tz) }

    func testAfternoonIsItsOwnDate() {
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 11, 14, 0)), "2026-06-11")
    }

    func testMidnightStaysInPreviousDay() {
        // Not strict midnight: 00:00 on the 12th still belongs to the 11th.
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 12, 0, 0)), "2026-06-11")
    }

    func testLateNightSessionStaysInOneDay() {
        // Working until 2am stays bucketed with the evening.
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 12, 2, 0)), "2026-06-11")
    }

    func testJustBeforeCutoffStaysInPreviousDay() {
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 12, 3, 59)), "2026-06-11")
    }

    func testCutoffRollsToNewDay() {
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 12, 4, 0)), "2026-06-12")
    }

    func testMorningIsNewDay() {
        XCTAssertEqual(boundary.logicalDate(for: date(2026, 6, 12, 9, 0)), "2026-06-12")
    }

    func testMakeDayCapturesTimezoneMetadata() {
        let start = date(2026, 6, 11, 22, 0)
        let day = boundary.makeDay(for: start, start: start.timeIntervalSince1970, end: start.timeIntervalSince1970 + 60)
        XCTAssertEqual(day.logicalDate, "2026-06-11")
        XCTAssertEqual(day.timezoneIdentifier, "America/New_York")
        XCTAssertEqual(day.cutoffHour, 4)
        // EDT in June is UTC-4.
        XCTAssertEqual(day.timezoneOffsetSeconds, -4 * 3600)
    }
}
