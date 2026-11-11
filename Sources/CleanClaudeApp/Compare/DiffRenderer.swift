import AppKit
import CleanCore

/// Builds inert attributed text once per picked file. TextKit draws only visible glyphs while scrolling.
@MainActor enum DiffRenderer {
    enum Side { case old, new }
    static func text(_ document: DiffDocument, path: String, side: Side?) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let highlighter = SyntaxHighlighter(path: path)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
        let defaults: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        for hunk in document.hunks {
            var oldState = SyntaxHighlighter.State(); var newState = SyntaxHighlighter.State()
            let heading = NSMutableAttributedString(string: hunk.header + "\n", attributes: defaults)
            heading.addAttribute(.foregroundColor, value: Palette.syntax(.keyword), range: NSRange(location: 0, length: heading.length))
            output.append(heading)
            let rows = side == nil ? hunk.lines.map { ($0 as DiffLine?, $0 as DiffLine?) } : paired(hunk.lines)
            for row in rows {
                let line = side == .old ? row.0 : row.1
                guard let line else { output.append(NSAttributedString(string: "\n", attributes: defaults)); continue }
                let tokens: [SyntaxHighlighter.Token]
                if line.kind == .removed { tokens = highlighter.tokens(in: line.text, state: &oldState) }
                else if line.kind == .added { tokens = highlighter.tokens(in: line.text, state: &newState) }
                else {
                    _ = highlighter.tokens(in: line.text, state: &oldState)
                    tokens = highlighter.tokens(in: line.text, state: &newState)
                }
                let prefix: String
                if let side { prefix = number(side == .old ? line.oldNumber : line.newNumber) + "  " }
                else { prefix = number(line.oldNumber) + " " + number(line.newNumber) + "  " }
                let marker = line.kind == .added ? "+ " : line.kind == .removed ? "− " : "  "
                let lead = prefix + marker
                let attributed = NSMutableAttributedString(string: lead + line.text + "\n", attributes: defaults)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                    range: NSRange(location: 0, length: lead.utf16.count))
                if line.kind == .added || line.kind == .removed {
                    attributed.addAttribute(.backgroundColor, value: Palette.diffTint(added: line.kind == .added),
                        range: NSRange(location: 0, length: attributed.length))
                }
                for token in tokens {
                    attributed.addAttribute(.foregroundColor, value: Palette.syntax(token.kind),
                        range: NSRange(location: lead.utf16.count + token.range.lowerBound, length: token.range.count))
                }
                for word in line.changedWords {
                    attributed.addAttribute(.backgroundColor, value: Palette.diffTint(added: line.kind == .added, strong: true),
                        range: NSRange(location: lead.utf16.count + word.lowerBound, length: word.count))
                }
                output.append(attributed)
            }
        }
        return output
    }

    private static func number(_ number: Int?) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, 5 - text.count)) + text
    }

    private static func paired(_ lines: [DiffLine]) -> [(DiffLine?, DiffLine?)] {
        var result: [(DiffLine?, DiffLine?)] = []; var i = 0
        while i < lines.count {
            if lines[i].kind == .removed {
                var removed: [DiffLine] = []; var added: [DiffLine] = []
                while i < lines.count && lines[i].kind == .removed { removed.append(lines[i]); i += 1 }
                while i < lines.count && lines[i].kind == .added { added.append(lines[i]); i += 1 }
                for j in 0..<max(removed.count, added.count) {
                    result.append((j < removed.count ? removed[j] : nil, j < added.count ? added[j] : nil))
                }
            } else if lines[i].kind == .added { result.append((nil, lines[i])); i += 1 }
            else { result.append((lines[i], lines[i])); i += 1 }
        }
        return result
    }
}
