import CleanCore
import Foundation
import Testing

@Suite("WorktreeListParser")
struct WorktreeListParserTests {
    typealias Record = WorktreeListParser.Record

    /// Builds porcelain -z output: each field NUL-terminated.
    private func porcelain(_ fields: [String]) -> Data {
        Data(fields.map { $0 + "\0" }.joined().utf8)
    }

    @Test func normalRecord() {
        let data = porcelain(["worktree /Users/me/repo", "HEAD abc123", "branch refs/heads/main", ""])
        #expect(WorktreeListParser.parse(data) == [
            Record(path: "/Users/me/repo", head: "abc123", branch: "main"),
        ])
    }

    @Test func pathWithSpacesAndQuote() {
        let path = #"/Users/me/My "quoted" repo/feature x"#
        let data = porcelain(["worktree \(path)", "HEAD abc", "branch refs/heads/feat/one", ""])
        let records = WorktreeListParser.parse(data)
        #expect(records.map(\.path) == [path])
        #expect(records.first?.branch == "feat/one")
    }

    @Test func detached() {
        let data = porcelain(["worktree /r/wt", "HEAD def456", "detached", ""])
        #expect(WorktreeListParser.parse(data) == [Record(path: "/r/wt", head: "def456", isDetached: true)])
    }

    @Test func bare() {
        let data = porcelain(["worktree /r/repo.git", "bare", ""])
        #expect(WorktreeListParser.parse(data) == [Record(path: "/r/repo.git", isBare: true)])
    }

    @Test func lockedWithAndWithoutReason() {
        let data = porcelain([
            "worktree /r/a", "HEAD 1", "branch refs/heads/a", "locked", "",
            "worktree /r/b", "HEAD 2", "branch refs/heads/b", "locked on a USB disk", "",
        ])
        let records = WorktreeListParser.parse(data)
        #expect(records.map(\.lockedReason) == ["", "on a USB disk"])
    }

    @Test func prunable() {
        let data = porcelain([
            "worktree /r/gone", "HEAD 3", "branch refs/heads/gone",
            "prunable gitdir file points to non-existent location", "",
        ])
        let record = WorktreeListParser.parse(data).first
        #expect(record?.prunableReason == "gitdir file points to non-existent location")
        #expect(record?.lockedReason == nil)
    }

    @Test func severalRecords() {
        let data = porcelain([
            "worktree /r/main", "HEAD 1", "branch refs/heads/main", "",
            "worktree /r/main-feat", "HEAD 2", "branch refs/heads/feat", "",
            "worktree /r/main-det", "HEAD 3", "detached", "",
        ])
        let records = WorktreeListParser.parse(data)
        #expect(records.map(\.path) == ["/r/main", "/r/main-feat", "/r/main-det"])
        #expect(records.map(\.branch) == ["main", "feat", nil])
        #expect(records.map(\.isDetached) == [false, false, true])
    }

    @Test func trailingNULHandling() {
        let fields = ["worktree /r/main", "HEAD 1", "branch refs/heads/main"]
        let expected = [Record(path: "/r/main", head: "1", branch: "main")]
        // Missing record terminator, normal terminator, and extra NULs all give the same record.
        #expect(WorktreeListParser.parse(porcelain(fields)) == expected)
        #expect(WorktreeListParser.parse(porcelain(fields + [""])) == expected)
        #expect(WorktreeListParser.parse(porcelain(fields + ["", "", ""])) == expected)
        // No trailing NUL at all on the last field.
        let unterminated = Data(fields.joined(separator: "\0").utf8)
        #expect(WorktreeListParser.parse(unterminated) == expected)
        #expect(WorktreeListParser.parse(Data()).isEmpty)
    }

    @Test func nonHeadsBranchAndUnknownAttributesKept() {
        let data = porcelain([
            "HEAD orphan-before-worktree", "worktree /r/x", "HEAD 9", "branch refs/remotes/origin/x",
            "future-attribute value", "",
        ])
        #expect(WorktreeListParser.parse(data) == [Record(path: "/r/x", head: "9", branch: "refs/remotes/origin/x")])
    }
}
