@testable import CleanCore
import Foundation
import Testing

@Suite("ClaudeProjectFolderName")
struct ClaudeProjectFolderNameTests {
    @Test func replacesEveryCharacterOutsideAlphanumericsWithADash() {
        #expect(ClaudeProjectFolderName.encode("/Users/me/Documents/GitHub/app") == "-Users-me-Documents-GitHub-app")
        #expect(ClaudeProjectFolderName.encode("/Users/me/.claude/worktrees/x") == "-Users-me--claude-worktrees-x")
        #expect(ClaudeProjectFolderName.encode("/a b/c_d-e.f") == "-a-b-c-d-e-f")
        #expect(ClaudeProjectFolderName.encode("/Repo42/AbZ09") == "-Repo42-AbZ09")
        #expect(ClaudeProjectFolderName.encode("") == "")
    }

    @Test func worksPerUTF16UnitLikeTheJavaScriptReplace() {
        #expect(ClaudeProjectFolderName.encode("/caf\u{E9}") == "-caf-")
        #expect(ClaudeProjectFolderName.encode("/x\u{1F600}y") == "-x--y", "an emoji is two UTF-16 units")
    }

    @Test func decodesOnlyUnambiguousNames() {
        let table = ClaudeProjectFolderName.decodingTable(candidates: [
            "/work/app",
            "/work/app",  // the same path twice is not an ambiguity
            "/work/a b",
            "/a/b-c",
            "/a/b/c",     // encodes like /a/b-c
        ])
        #expect(table["-work-app"] == "/work/app")
        #expect(table["-work-a-b"] == "/work/a b")
        #expect(table["-a-b-c"] == nil, "two different paths encode to this name, so it stays raw")
        #expect(table.count == 2)
    }

    @Test func noCandidatesMeansAnEmptyTable() {
        #expect(ClaudeProjectFolderName.decodingTable(candidates: []).isEmpty)
    }
}
