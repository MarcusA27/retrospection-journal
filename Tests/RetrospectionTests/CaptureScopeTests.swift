import XCTest
@testable import Retrospection

final class CaptureScopeTests: XCTestCase {
    private let claude = "com.anthropic.claudefordesktop"

    func testAllowOnlyCapturesOnlyListedApp() {
        let scope = CaptureScope(allowOnly: [claude], ignore: [])
        XCTAssertTrue(scope.shouldCapture(bundleID: claude))
        XCTAssertFalse(scope.shouldCapture(bundleID: "com.apple.Safari"))
        XCTAssertFalse(scope.shouldCapture(bundleID: "com.apple.mail"))
    }

    func testAllowOnlyRejectsUnknownBundle() {
        let scope = CaptureScope(allowOnly: [claude], ignore: [])
        XCTAssertFalse(scope.shouldCapture(bundleID: nil))
    }

    func testEmptyAllowFallsBackToIgnoreList() {
        let scope = CaptureScope(allowOnly: [], ignore: ["com.apple.Terminal"])
        XCTAssertTrue(scope.shouldCapture(bundleID: "com.apple.Safari"))
        XCTAssertFalse(scope.shouldCapture(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(scope.shouldCapture(bundleID: nil))   // unknown app, nothing ignored
    }
}
