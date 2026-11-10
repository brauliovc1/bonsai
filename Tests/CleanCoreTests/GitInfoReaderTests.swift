@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Git info: last commits, remotes, upstream")
struct GitInfoReaderTests {
    /// A commit by a named author with a multi-line message.
    private func commit(_ fixture: GitFixture, in folder: URL, file: String, message: String, author: String) async throws {
        try fixture.write("\(file)\n", to: file, in: folder)
        try await fixture.run(["add", "-A"], in: folder, adding: ["GIT_AUTHOR_NAME": author])
        try await fixture.run(["commit", "--quiet", "-m", message], in: folder, adding: ["GIT_AUTHOR_NAME": author])
    }

    @Test func theScanReadsLastCommitsAndRemotesFromRealRepos() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("alpha")
        let feature = try await fixture.addSiblingWorktree(to: repo, name: "feature")
        try await commit(fixture, in: feature, file: "a.md", message: "Add the a page\n\nLonger story,\ntwo lines.",
                         author: "Ana Pérez")
        let detached = try await fixture.addWorktree(to: repo, at: fixture.scanRoot.appending(path: "alpha-probe"),
                                                     detached: true)
        try await commit(fixture, in: detached, file: "probe.md", message: "Probe", author: "Bo")
        // A composed non-ASCII folder name, registered the way a shell or the Claude app would (mkdir + add from inside).
        // Inside the repo, so git run from inside the new folder finds it.
        try FileManager.default.createDirectory(at: repo.appending(path: ".claude/worktrees"), withIntermediateDirectories: true)
        let composed = repo.path + "/.claude/worktrees/alpha caf\u{E9} \u{1F333}"
        #expect(mkdir(composed, 0o755) == 0)
        try await fixture.run(["worktree", "add", "--quiet", "-b", "cafe", "."], in: URL(fileURLWithPath: composed))
        try await commit(fixture, in: URL(fileURLWithPath: composed), file: "c.md", message: "Añade café ☕",
                         author: "Zoë")
        let gone = try await fixture.addSiblingWorktree(to: repo, name: "gone")
        try fixture.deleteFolder(gone)
        try await fixture.run(["remote", "add", "upstream",
                               "https://braulio:\(RemoteURLTests.token)@github.com/brauliovc1/alpha.git"], in: repo)

        let result = await Scanner(environment: fixture.environment())
            .scan(roots: [fixture.scanRoot], includeSizes: false, includeGitDetails: true)
        #expect(result.worktrees.count == 5)
        func worktree(_ suffix: String) throws -> Worktree {
            try #require(result.worktrees.first { $0.path.hasSuffix(suffix) })
        }

        let featureCommit = try #require(result.lastCommit(of: try worktree("alpha-feature")))
        #expect(featureCommit.subject == "Add the a page")
        #expect(featureCommit.message == "Add the a page\n\nLonger story,\ntwo lines.")
        #expect(featureCommit.author == "Ana Pérez")
        #expect(featureCommit.sha == (try worktree("alpha-feature")).head)
        #expect(abs(featureCommit.date.timeIntervalSinceNow) < 600)

        let probe = try worktree("alpha-probe")
        #expect(probe.isDetached)
        #expect(result.lastCommit(of: probe)?.subject == "Probe")
        #expect(result.lastCommit(of: probe)?.sha == probe.head)

        let cafe = try #require(result.worktrees.first { $0.branch == "cafe" })
        #expect(result.lastCommit(of: cafe)?.subject == "Añade café ☕")
        #expect(result.lastCommit(of: cafe)?.author == "Zoë")

        #expect(result.lastCommit(of: try worktree("alpha-gone"))?.subject == "Initial commit", "the record's HEAD, no folder needed")
        #expect(result.lastCommit(of: try worktree("/alpha"))?.subject == "Initial commit")

        let remotes = result.remotes(of: try worktree("/alpha"))
        #expect(remotes.map(\.name) == ["origin", "upstream"])
        #expect(remotes.first?.url.hasPrefix(fixture.remotes.path) == true)
        #expect(remotes.last?.url == "https://github.com/brauliovc1/alpha.git")
        let json = String(decoding: try CleanJSON.encoder().encode(result), as: UTF8.self)
        #expect(!json.contains(RemoteURLTests.token))
        #expect(json.contains("Añade café"))

        let plain = await Scanner(environment: fixture.environment()).scan(roots: [fixture.scanRoot], includeSizes: false)
        #expect(plain.lastCommits == nil && plain.remotes == nil, "only when asked for")
        let decoded = try CleanJSON.decoder().decode(ScanResult.self, from: try CleanJSON.encoder().encode(result))
        #expect(decoded.lastCommits == result.lastCommits)
        #expect(decoded.remotes == result.remotes)
    }

    @Test func recentCommitsAndUpstreamAheadBehind() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("beta")
        let task = try await fixture.addSiblingWorktree(to: repo, name: "task")
        for index in 1...4 {
            try await commit(fixture, in: task, file: "\(index).md", message: "Step \(index)", author: "Ana")
        }
        try await fixture.run(["push", "--quiet", "-u", "origin", "task"], in: task)
        try await fixture.run(["reset", "--quiet", "--hard", "HEAD~1"], in: task)
        try await commit(fixture, in: task, file: "5.md", message: "Step 5", author: "Bo")
        try await commit(fixture, in: task, file: "6.md", message: "Step 6", author: "Cy")
        let listed = try await WorktreeScanner(git: fixture.git, cursorWorktreesDirectory: fixture.home)
            .worktrees(in: repo)
        let worktree = try #require(listed.first { $0.branch == "task" })
        let reader = GitInfoReader(git: fixture.git)

        let commits = try await reader.recentCommits(of: worktree)
        #expect(commits.map(\.subject) == ["Step 6", "Step 5", "Step 3", "Step 2", "Step 1"])
        #expect(commits.map(\.author).prefix(2) == ["Cy", "Bo"])
        #expect(try await reader.recentCommits(of: worktree, count: 2).count == 2)

        #expect(try await reader.upstream(of: worktree) == UpstreamStatus(name: "origin/task", ahead: 2, behind: 1))
        let main = try #require(listed.first { $0.isMain })
        #expect(try await reader.upstream(of: main) == UpstreamStatus(name: "origin/main"))

        // A branch whose name another branch extends ("task/sub"), a branch without an upstream, detached.
        try await fixture.run(["branch", "task-free"], in: repo)
        var free = worktree
        free.branch = "task-free"
        #expect(try await reader.upstream(of: free) == nil)
        var detached = worktree
        detached.branch = nil
        #expect(try await reader.upstream(of: detached) == nil)

        // The remote branch deleted: gone.
        try await fixture.run(["push", "--quiet", "origin", "--delete", "task"], in: task)
        #expect(try await reader.upstream(of: worktree)?.isGone == true)
    }

    @Test func nonASCIIBranchNamesFindTheirUpstream() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("gamma")
        // Created with precomposition on, so the branch is stored composed ("é" as one character)...
        try await fixture.run(["config", "core.precomposeunicode", "true"], in: repo)
        let task = try await fixture.addSiblingWorktree(to: repo, name: "ramé", branch: "ram\u{E9}")
        try await commit(fixture, in: task, file: "x.md", message: "x", author: "A")
        try await fixture.run(["push", "--quiet", "-u", "origin", "HEAD"], in: task)
        try await commit(fixture, in: task, file: "y.md", message: "y", author: "A")
        // ...then read with it off: a "refs/heads/ramé" argument now reaches git decomposed and matches nothing.
        try await fixture.run(["config", "core.precomposeunicode", "false"], in: repo)
        let listed = try await WorktreeScanner(git: fixture.git, cursorWorktreesDirectory: fixture.home)
            .worktrees(in: repo)
        let worktree = try #require(listed.first { $0.branch?.hasPrefix("ram") == true })
        let upstream = try await GitInfoReader(git: fixture.git).upstream(of: worktree)
        #expect(upstream?.ahead == 1)
        #expect(upstream?.name.hasPrefix("origin/ram") == true)
    }
}
