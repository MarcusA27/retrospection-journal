import SwiftUI

/// Renders a journal entry's markdown body into clean, readable blocks.
/// The entries are simple — paragraphs, the occasional `> quote`, inline **bold**/*italic* and
/// (timestamps) — so a lightweight block renderer reads better than a heavyweight markdown engine.
struct JournalText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(JournalBlock.parse(text).enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .textSelection(.enabled)
    }
}

enum JournalBlock {
    case heading(String)
    case quote(AttributedString)
    case paragraph(AttributedString)

    @ViewBuilder var view: some View {
        switch self {
        case .heading(let s):
            Text(s).font(.system(.title3, design: .serif).weight(.semibold))
                .padding(.top, 4)
        case .quote(let a):
            Text(a)
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    Rectangle().frame(width: 2).foregroundStyle(.secondary.opacity(0.35))
                }
        case .paragraph(let a):
            Text(a).font(.system(.body, design: .serif)).lineSpacing(5)
        }
    }

    static func parse(_ text: String) -> [JournalBlock] {
        text.components(separatedBy: "\n\n").compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if t.hasPrefix("# ") { return .heading(String(t.dropFirst(2))) }
            if t.hasPrefix("> ") {
                let inner = t.components(separatedBy: "\n")
                    .map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }
                    .joined(separator: " ")
                return .quote(md(inner))
            }
            return .paragraph(md(t))
        }
    }

    static func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
