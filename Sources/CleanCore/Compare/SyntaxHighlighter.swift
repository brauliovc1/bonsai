import Foundation

/// Small lexical highlighter. State is carried independently along each side of a hunk.
public struct SyntaxHighlighter: Sendable {
    public enum Kind: String, Sendable { case comment, string, number, keyword, type, plain }
    public struct Token: Sendable, Equatable { public let range: Range<Int>; public let kind: Kind }
    public struct State: Sendable { var blockEnd: String?; public init() {} }
    public let language: String
    public init(path: String) { language = URL(fileURLWithPath: path).pathExtension.lowercased() }
    public static let extensions: Set<String> = ["swift", "dart", "ts", "tsx", "js", "jsx", "py", "kt", "kts", "java", "go", "rs", "json", "yaml", "yml", "md", "sh", "bash", "zsh", "css", "html", "htm"]
    static let keywords = Set("actor as async await break case catch class const continue def defer do else enum export extends false final fn for from func function guard if impl import in interface is let match mut new nil none null override package private public return self static struct super switch this throw throws true try type typeof val var void when where while with yield".split(separator: " ").map(String.init))

    public func tokens(in text: String, state: inout State) -> [Token] {
        guard Self.extensions.contains(language) else { return [] }
        let units = Array(text.utf16)
        var result: [Token] = []; var i = 0
        func has(_ value: String, at offset: Int) -> Bool {
            let match = Array(value.utf16)
            return offset + match.count <= units.count && units[offset..<(offset + match.count)].elementsEqual(match)
        }
        func append(_ start: Int, _ end: Int, _ kind: Kind) { if start < end { result.append(Token(range: start..<end, kind: kind)) } }
        while i < units.count {
            let start = i
            if let end = state.blockEnd {
                while i < units.count && !has(end, at: i) { i += 1 }
                if i < units.count { i += end.utf16.count; state.blockEnd = nil }
                append(start, i, end == "*/" || end == "-->" ? .comment : .string); continue
            }
            let hashComment = ["py", "yaml", "yml", "sh", "bash", "zsh"].contains(language)
            if has("//", at: i) && !["json", "md", "html", "htm", "css"].contains(language) || hashComment && has("#", at: i) {
                append(i, units.count, .comment); break
            }
            if has("/*", at: i), !hashComment { state.blockEnd = "*/"; i += 2; append(start, i, .comment); continue }
            if ["html", "htm", "md"].contains(language), has("<!--", at: i) { state.blockEnd = "-->"; i += 4; append(start, i, .comment); continue }
            if has("\"\"\"", at: i) || has(String(repeating: "'", count: 3), at: i) {
                state.blockEnd = has("\"\"\"", at: i) ? "\"\"\"" : String(repeating: "'", count: 3); i += 3; append(start, i, .string); continue
            }
            if units[i] == 34 || units[i] == 39 || units[i] == 96 {
                let quote = units[i]; i += 1
                while i < units.count {
                    if units[i] == 92 { i = min(i + 2, units.count) }
                    else if units[i] == quote { i += 1; break }
                    else { i += 1 }
                }
                if quote == 96 && (i == units.count && units.last != 96) { state.blockEnd = "`" }
                append(start, i, .string); continue
            }
            if units[i] >= 48 && units[i] <= 57 {
                i += 1
                while i < units.count && (isWord(units[i]) || units[i] == 46 || units[i] == 95) { i += 1 }
                append(start, i, .number); continue
            }
            if isWord(units[i]) {
                i += 1
                while i < units.count && isWord(units[i]) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                append(start, i, Self.keywords.contains(word) ? .keyword : word.first?.isUppercase == true ? .type : .plain)
            } else { i += 1 }
        }
        return result
    }

    private func isWord(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || unit == 95
    }
}
