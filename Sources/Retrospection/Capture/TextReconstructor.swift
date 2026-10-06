import Foundation
import CoreGraphics

/// macOS virtual key codes for the editing keys we interpret. Everything else is treated as text
/// via the event's produced Unicode string, so keyboard layout and dead keys are respected.
private enum KeyCode {
    static let delete: Int64 = 51        // Backspace
    static let forwardDelete: Int64 = 117
    static let ret: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
    static let home: Int64 = 115
    static let end: Int64 = 119
}

/// Reconstructs clean, readable text from a raw keystroke stream for a single entry.
///
/// It maintains an editable buffer with a cursor and interprets the common editing keys:
/// backspace / forward-delete (incl. word and line variants), return, tab, and horizontal
/// navigation. What it deliberately does NOT track: mouse-based cursor repositioning and vertical
/// (up/down) navigation — those are invisible to a keystroke tap, so the stream simply continues
/// at the current cursor. Reconstruction is faithful for linear typing-and-correcting, approximate
/// when the user clicks around mid-sentence. We store text, never keycodes.
final class TextReconstructor {
    private var buffer: [Character] = []
    private var cursor: Int = 0

    var isEmpty: Bool { buffer.allSatisfy { $0 == "\n" || $0 == "\t" || $0 == " " } }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        cursor = 0
    }

    /// The reconstructed text, with trailing whitespace on each line trimmed and outer blank lines removed.
    func finalText() -> String {
        let raw = String(buffer)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies one keyDown event. `characters` is the Unicode string the event produced (may be empty).
    func apply(keyCode: Int64, characters: String, flags: CGEventFlags) {
        let cmd = flags.contains(.maskCommand)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)

        switch keyCode {
        case KeyCode.delete:
            if cmd { deleteToLineStart() } else if option { deletePreviousWord() } else { backspace() }
        case KeyCode.forwardDelete:
            forwardDelete()
        case KeyCode.ret, KeyCode.keypadEnter:
            insert("\n")
        case KeyCode.tab:
            insert("\t")
        case KeyCode.left:
            if cmd { cursor = lineStart() } else if option { cursor = wordLeft() } else { moveLeft() }
        case KeyCode.right:
            if cmd { cursor = lineEnd() } else if option { cursor = wordRight() } else { moveRight() }
        case KeyCode.home:
            cursor = 0
        case KeyCode.end:
            cursor = buffer.count
        case KeyCode.up, KeyCode.down, KeyCode.escape:
            break // not tracked — see type doc
        default:
            // Plain text. Skip command/control shortcuts (e.g. Cmd-C, Ctrl-A) which aren't input.
            guard !cmd, !control else { return }
            insertProducedText(characters)
        }
    }

    // MARK: - Editing primitives

    private func insertProducedText(_ s: String) {
        // Filter out non-printing control characters that some keys still emit (e.g. \u{7f}).
        let printable = s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }
        guard !printable.isEmpty else { return }
        insert(String(String.UnicodeScalarView(printable)))
    }

    private func insert(_ s: String) {
        let chars = Array(s)
        buffer.insert(contentsOf: chars, at: cursor)
        cursor += chars.count
    }

    private func backspace() {
        guard cursor > 0 else { return }
        buffer.remove(at: cursor - 1)
        cursor -= 1
    }

    private func forwardDelete() {
        guard cursor < buffer.count else { return }
        buffer.remove(at: cursor)
    }

    private func deleteToLineStart() {
        let start = lineStart()
        guard start < cursor else { return }
        buffer.removeSubrange(start..<cursor)
        cursor = start
    }

    private func deletePreviousWord() {
        let target = wordLeft()
        guard target < cursor else { return }
        buffer.removeSubrange(target..<cursor)
        cursor = target
    }

    private func moveLeft() { if cursor > 0 { cursor -= 1 } }
    private func moveRight() { if cursor < buffer.count { cursor += 1 } }

    // MARK: - Position helpers

    private func lineStart() -> Int {
        var i = cursor
        while i > 0 && buffer[i - 1] != "\n" { i -= 1 }
        return i
    }

    private func lineEnd() -> Int {
        var i = cursor
        while i < buffer.count && buffer[i] != "\n" { i += 1 }
        return i
    }

    private func wordLeft() -> Int {
        var i = cursor
        while i > 0 && buffer[i - 1].isWhitespace { i -= 1 }
        while i > 0 && !buffer[i - 1].isWhitespace { i -= 1 }
        return i
    }

    private func wordRight() -> Int {
        var i = cursor
        while i < buffer.count && buffer[i].isWhitespace { i += 1 }
        while i < buffer.count && !buffer[i].isWhitespace { i += 1 }
        return i
    }
}
