@testable import CleanCore
import Foundation
import Testing

struct BranchHistoryValueTests {
    @Test func creationUsesTheReflogTimestampAndOldestCreationRecord() throws {
        let sha = String(repeating: "a", count: 40)
        let newer = "\(sha)\0refs/heads/new@{2000 +0000}\0branch: Created from other\0\n"
        let older = "\(sha)\0refs/heads/new@{1000 +0000}\0branch: Created from main\0\n"
        let origin = try #require(BranchReflog.creation(in: Data((newer + older).utf8)))
        #expect(origin.source == .reflog && origin.parent == "main")
        #expect(origin.date == Date(timeIntervalSince1970: 1000) && origin.isCertain)
        #expect(origin.atSHA == sha)
    }

    @Test func missingOrMalformedCreationIsUnknown() {
        #expect(BranchReflog.creation(in: Data()) == nil)
        #expect(BranchReflog.creation(in: Data("not-a-sha\0name@{2}\0branch: Created from main\0".utf8)) == nil)
        let sha = String(repeating: "b", count: 40)
        #expect(BranchReflog.creation(in: Data("\(sha)\0name@{0}\0commit: Initial commit\0".utf8)) == nil)
        #expect(BranchReflog.creation(in: Data("\(sha)\0name@{not-a-date}\0branch: Created from main\0".utf8)) == nil)
    }

    @Test func familyReadsStackBothWaysAndStopsAtBase() {
        let family = BranchFamily(origins: ["c": origin("b"), "b": origin("a"), "a": origin("main")])
        #expect(family.chain(from: "c", through: "main").branches == ["c", "b", "a", "main"])
        #expect(family.children(of: "a") == ["b"])
        #expect(family.children(of: "main") == ["a"])
        #expect(family.chain(from: "c", through: "b").branches == ["c", "b"])
    }

    @Test func cyclesAndMissingParentsEndWithoutRecursingForever() {
        let family = BranchFamily(origins: ["a": origin("b"), "b": origin("a")])
        #expect(family.chain(from: "a", through: "main").branches == ["a", "b"])
        #expect(family.chain(from: "a", through: "main").cycleAt == "a")
        #expect(family.chain(from: "unrelated", through: "main").branches == ["unrelated"])
    }

    @Test func sharedLogScaleKeepsSmallBranchesVisible() {
        let small = BranchMapLayout.fraction(3, maximum: 300)
        #expect(small > 0.2 && small < 0.3)
        #expect(BranchMapLayout.fraction(300, maximum: 300) == 1)
        #expect(BranchMapLayout.fraction(0, maximum: 300) == 0)
        #expect(BranchMapLayout.fraction(-1, maximum: 300) == 0)
        #expect(BranchMapLayout.fraction(3, maximum: 0) == 1)
    }

    @Test func sortingUsesDistanceThenNameAndKeepsUnknownHistoryLast() {
        let a = entry("a", ahead: 3, behind: 0, date: 10)
        let b = entry("b", ahead: 0, behind: 300, date: 100)
        let c = entry("c", ahead: 1, behind: 1, date: 50)
        let d = entry("d", ahead: nil, behind: nil, date: 200)
        let rows = [d, b, a, c]
        #expect(BranchMapLayout.sorted(rows, by: .closest).map(\.name) == ["c", "a", "b", "d"])
        #expect(BranchMapLayout.sorted(rows, by: .recent).map(\.name) == ["d", "b", "c", "a"])
        #expect(BranchMapLayout.sorted(rows, by: .name).map(\.name) == ["a", "b", "c", "d"])
        #expect(b.metrics.isMerged)
        #expect(!d.metrics.isMerged)
    }

    private func origin(_ parent: String) -> BranchOrigin { BranchOrigin(parent: parent, source: .reflog, reason: "fixture") }
    private func entry(_ name: String, ahead: Int?, behind: Int?, date: TimeInterval) -> BranchMapEntry {
        let commit = BranchHistoryCommit(sha: name, subject: name, date: Date(timeIntervalSince1970: date))
        return BranchMapEntry(ref: "refs/heads/" + name, name: name, sha: name,
                              metrics: BranchMapMetrics(ahead: ahead, behind: behind, fork: nil, tip: commit))
    }
}
