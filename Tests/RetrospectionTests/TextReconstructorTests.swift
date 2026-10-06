import XCTest
import CoreGraphics
@testable import Retrospection

final class TextReconstructorTests: XCTestCase {
    private var r = TextReconstructor()

    override func setUp() { r = TextReconstructor() }

    /// Types a literal string as a sequence of plain keystrokes.
    private func type(_ s: String) {
        for ch in s { r.apply(keyCode: 200, characters: String(ch), flags: []) }
    }

    private func press(_ keyCode: Int64, _ flags: CGEventFlags = []) {
        r.apply(keyCode: keyCode, characters: "", flags: flags)
    }

    func testPlainTyping() {
        type("hello world")
        XCTAssertEqual(r.finalText(), "hello world")
    }

    func testBackspaceCorrects() {
        type("helo")
        press(51)            // backspace -> "hel"
        type("lo")           // -> "hello"
        XCTAssertEqual(r.finalText(), "hello")
    }

    func testReturnMakesNewline() {
        type("first")
        press(36)            // return
        type("second")
        XCTAssertEqual(r.finalText(), "first\nsecond")
    }

    func testForwardDeleteAtLineStart() {
        type("ab")
        press(115)           // Home -> cursor 0
        press(117)           // forward delete -> "b"
        XCTAssertEqual(r.finalText(), "b")
    }

    func testLeftThenInsertMidWord() {
        type("helo")
        press(123)           // left, cursor before 'o'
        type("l")            // insert 'l' -> "hello"
        XCTAssertEqual(r.finalText(), "hello")
    }

    func testOptionBackspaceDeletesWord() {
        type("foo bar")
        press(51, .maskAlternate)   // delete previous word -> "foo "
        XCTAssertEqual(r.finalText(), "foo")   // trailing space trimmed by finalText
    }

    func testCommandBackspaceDeletesToLineStart() {
        type("keep")
        press(36)
        type("discard this")
        press(51, .maskCommand)     // delete to line start
        XCTAssertEqual(r.finalText(), "keep")
    }

    func testCommandShortcutsAreNotTyped() {
        type("ab")
        r.apply(keyCode: 8, characters: "c", flags: .maskCommand)  // Cmd-C: must not insert 'c'
        XCTAssertEqual(r.finalText(), "ab")
    }

    func testTrailingWhitespaceTrimmedPerLine() {
        type("line one   ")
        press(36)
        type("line two")
        XCTAssertEqual(r.finalText(), "line one\nline two")
    }

    func testIsEmptyIgnoresWhitespaceOnly() {
        type("   ")
        press(36)
        XCTAssertTrue(r.isEmpty)
    }
}
