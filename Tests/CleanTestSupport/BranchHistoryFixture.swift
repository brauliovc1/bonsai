import CleanCore
import Foundation

/// Three stacked branches with fixed commit/reflog dates and a local bare origin.
public struct BranchHistoryFixture: Sendable {
    public let fixture: GitFixture
    public let repo: URL
    public let seed: String
    public let epoch: TimeInterval = 1_700_000_000

    public static func make() async throws -> BranchHistoryFixture {
        let fixture = try GitFixture()
        let repo = try await fixture.makeRepo("history")
        let world = BranchHistoryFixture(fixture: fixture, repo: repo, seed: "")
        try await world.commit("seed.txt", date: world.epoch, subject: "Shared starting point")
        let seed = try await fixture.run(["rev-parse", "HEAD"], in: repo)
        let result = BranchHistoryFixture(fixture: fixture, repo: repo, seed: seed)
        try await fixture.run(["push", "--quiet", "origin", "main"], in: repo)
        try await fixture.run(["remote", "set-head", "origin", "main"], in: repo)
        for (index, name) in ["a", "b", "c"].enumerated() {
            let parent = index == 0 ? "main" : ["a", "b", "c"][index - 1]
            try await result.branch(name, from: parent, date: result.epoch + Double(index + 1) * 10_000)
            try await result.commit(name + ".txt", date: result.epoch + Double(index + 1) * 10_000 + 100, subject: "Work on " + name)
        }
        try await fixture.run(["checkout", "--quiet", "main"], in: repo)
        return result
    }

    public func branch(_ name: String, from parent: String, date: TimeInterval) async throws {
        try await fixture.run(["checkout", "--quiet", "-b", name, parent], in: repo, adding: dates(date))
    }

    public func commit(_ file: String, date: TimeInterval, subject: String = "Change") async throws {
        try fixture.write(file + "\n", to: file, in: repo)
        try await fixture.run(["add", "--all"], in: repo)
        try await fixture.run(["commit", "--quiet", "-m", subject], in: repo, adding: dates(date))
    }

    public func dates(_ date: TimeInterval) -> [String: String] {
        let value = "\(Int(date)) +0000"
        return ["GIT_AUTHOR_DATE": value, "GIT_COMMITTER_DATE": value]
    }

    public func git() throws -> GitReadOnly {
        try GitReadOnly(repository: repo, executable: fixture.git.executable, timeout: TestWait.limit)
    }

    public func sha(_ ref: String) async throws -> String { try await fixture.run(["rev-parse", ref], in: repo) }
    public func remove() { fixture.remove() }
}
