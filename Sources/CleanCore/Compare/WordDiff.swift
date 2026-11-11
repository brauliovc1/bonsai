import Foundation

/// Bounded token LCS. Very long lines use a linear prefix/suffix comparison instead.
public enum WordDiff {
    public static func ranges(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>]) {
        let a = tokens(old); let b = tokens(new)
        guard a.count <= 256, b.count <= 256 else { return linear(old, new) }
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty && !b.isEmpty {
            for i in (0..<a.count).reversed() {
                for j in (0..<b.count).reversed() {
                    lengths[i][j] = a[i].text == b[j].text ? 1 + lengths[i + 1][j + 1] : max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }
        var oldRanges: [Range<Int>] = []; var newRanges: [Range<Int>] = []
        var i = 0; var j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i].text == b[j].text { i += 1; j += 1 }
            else if i < a.count && (j == b.count || lengths[i + 1][j] >= lengths[i][j + 1]) { oldRanges.append(a[i].range); i += 1 }
            else { newRanges.append(b[j].range); j += 1 }
        }
        return (oldRanges, newRanges)
    }

    private struct Token { let text: String; let range: Range<Int> }
    private static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []; var offset = 0; var current = ""; var start = 0; var previous = -1
        for char in text {
            let kind = char.isLetter || char.isNumber || char == "_" ? 0 : char.isWhitespace ? 1 : 2
            if kind != previous || kind == 2 {
                if !current.isEmpty { result.append(Token(text: current, range: start..<offset)) }
                current = ""; start = offset
            }
            current.append(char); offset += String(char).utf16.count; previous = kind
        }
        if !current.isEmpty { result.append(Token(text: current, range: start..<offset)) }
        return result
    }

    private static func linear(_ old: String, _ new: String) -> (old: [Range<Int>], new: [Range<Int>]) {
        let a = Array(old.utf16); let b = Array(new.utf16)
        var start = 0; var end = 0
        while start < min(a.count, b.count) && a[start] == b[start] { start += 1 }
        while end < min(a.count, b.count) - start && a[a.count - end - 1] == b[b.count - end - 1] { end += 1 }
        return (start < a.count - end ? [start..<(a.count - end)] : [], start < b.count - end ? [start..<(b.count - end)] : [])
    }
}
