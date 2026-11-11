import CleanCore
import Foundation
import Testing

@Suite("Compare diff parsing and highlighting")
struct CompareDiffTests {
    @Test func linesWordsAndMarkers() throws {
        let text = "@@ -10,2 +20,2 @@ func hello()\r\n-old value\r\n+new value\r\n context\r\n\\ No newline at end of file\r\n"
        let doc = DiffParser.parse(Data(text.utf8))
        let hunk = try #require(doc.hunks.first)
        #expect(hunk.function == "func hello()")
        #expect(hunk.lines[0].oldNumber == 10 && hunk.lines[0].newNumber == nil)
        #expect(hunk.lines[1].newNumber == 20 && hunk.lines[1].oldNumber == nil)
        #expect(hunk.lines[2].oldNumber == 11 && hunk.lines[2].newNumber == 21)
        #expect(hunk.lines[3].kind == .noNewline)
        #expect(hunk.lines[0].changedWords == [0..<3])
        #expect(hunk.lines[1].changedWords == [0..<3])
    }

    @Test func bytesTabsAndLongLines() {
        let bytes = Data([64,64,32,45,49,32,43,49,32,64,64,10,43,9,255,27,10])
        let doc = DiffParser.parse(bytes)
        #expect(doc.hunks.first?.lines.first?.text == "\\t\\xFF\\x1B")
        let old = String(repeating: "a ", count: 10_000) + "old"
        let new = String(repeating: "a ", count: 10_000) + "new"
        #expect(WordDiff.ranges(old: old, new: new).old == [20_000..<20_003])
    }

    @Test(arguments: ["swift", "dart", "ts", "tsx", "js", "jsx", "py", "kt", "java", "go", "rs", "json", "yaml", "yml", "md", "sh", "css", "html"])
    func languages(_ ext: String) {
        let highlighter = SyntaxHighlighter(path: "file." + ext)
        var state = SyntaxHighlighter.State()
        let tokens = highlighter.tokens(in: "let Name = \"hello\" + 42", state: &state)
        #expect(tokens.contains { $0.kind == .string })
        #expect(tokens.contains { $0.kind == .number })
        #expect(tokens.contains { $0.kind == .keyword })
    }

    @Test func multilineState() {
        let highlighter = SyntaxHighlighter(path: "file.swift")
        var state = SyntaxHighlighter.State()
        _ = highlighter.tokens(in: "/* start", state: &state)
        let next = highlighter.tokens(in: "still comment */ let answer = 42", state: &state)
        #expect(next.first?.kind == .comment)
        #expect(next.contains { $0.kind == .keyword })
        _ = highlighter.tokens(in: "let text = \"\"\"first", state: &state)
        #expect(highlighter.tokens(in: "second\"\"\"", state: &state).first?.kind == .string)
    }
}
