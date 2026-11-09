import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Worktree details panel and remote credentials")
@MainActor
struct WorktreeDetailsModelTests {
    static let token = "ghp_R2d2C3poX9wingBB8leiaH4nSolo0042"

    private func commit(_ fixture: GitFixture, _ message: String, in folder: URL) async throws {
        try fixture.write("\(message)\n", to: "\(message).md", in: folder)
        try await fixture.run(["add", "-A"], in: folder)
        try await fixture.run(["commit", "--quiet", "-m", message], in: folder)
    }

    @Test func theCommitsAndAheadBehindAreReadOnlyWhenThePanelLoads() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        let task = try await fixture.addSiblingWorktree(to: repo, name: "task")
        for step in 1...4 { try await commit(fixture, "Step \(step)", in: task) }
        try await fixture.run(["push", "--quiet", "-u", "origin", "task"], in: task)
        try await fixture.run(["reset", "--quiet", "--hard", "HEAD~1"], in: task)
        try await commit(fixture, "Step 5", in: task)
        try await commit(fixture, "Step 6", in: task)
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        let row = try #require(model.row(task))
        #expect(row.lastCommitText == "Step 6", "the scan reads the last commit only")

        #expect(model.details.state(for: row) == .notLoaded)
        model.selection = [row.id]
        #expect(model.isShowingDetails)
        #expect(model.details.loadCount == 0, "selecting doesn't read; the panel does when it shows the row")

        await model.details.load(for: row)
        guard case .loaded(let history) = model.details.state(for: row) else {
            Issue.record("not loaded: \(model.details.state(for: row))")
            return
        }
        #expect(history.commits.map(\.subject) == ["Step 6", "Step 5", "Step 3", "Step 2", "Step 1"])
        #expect(history.commits.allSatisfy { $0.author == "Fixture" })
        #expect(history.upstream == UpstreamStatus(name: "origin/task", ahead: 2, behind: 1))
        await model.details.load(for: row)
        #expect(model.details.loadCount == 1, "read once while the row is the same")

        try await commit(fixture, "Step 7", in: task)
        await app.refresh()
        let moved = try #require(model.row(task))
        #expect(moved.detailsKey != row.detailsKey)
        #expect(model.details.state(for: moved) == .notLoaded, "HEAD moved: read again")
        await model.details.load(for: moved)
        guard case .loaded(let again) = model.details.state(for: moved) else {
            Issue.record("not loaded again")
            return
        }
        #expect(again.commits.first?.subject == "Step 7")
        #expect(again.upstream?.ahead == 3)
        #expect(model.details.loadCount == 2)

        let main = try #require(model.allRows.first { $0.worktree.isMain })
        await model.details.load(for: main)
        guard case .loaded(let mainHistory) = model.details.state(for: main) else {
            Issue.record("main not loaded")
            return
        }
        #expect(mainHistory.commits.map(\.subject) == ["Initial commit"])
        #expect(mainHistory.upstream == UpstreamStatus(name: "origin/main"))
        #expect(model.details.state(for: moved) == .notLoaded, "one row at a time")
    }

    @Test func remoteCredentialsNeverReachTheRowsTheSearchOrTheJSON() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("secret")
        try await fixture.addSiblingWorktree(to: repo, name: "task")
        try await fixture.run(["remote", "add", "upstream",
                               "https://braulio:\(Self.token)@github.com/brauliovc1/secret.git"], in: repo)
        try await fixture.run(["remote", "set-url", "--push", "origin",
                               "https://x-access-token:\(Self.token)@github.com/brauliovc1/secret.git"], in: repo)
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))

        let group = try #require(model.groups.first)
        #expect(group.remotes.map(\.name) == ["origin", "upstream"])
        #expect(group.remotes.first?.pushURL == "https://github.com/brauliovc1/secret.git")
        #expect(group.remotes.last?.url == "https://github.com/brauliovc1/secret.git")
        let texts = [group.remotesHelp, group.remoteText ?? ""] + model.allRows.flatMap { row in
            row.remotes.flatMap { [$0.url, $0.pushURL ?? ""] }
        }
        #expect(texts.allSatisfy { !$0.contains(Self.token) && !$0.contains("braulio:") })
        model.searchText = String(Self.token.suffix(12))
        #expect(model.rows.isEmpty, "a token can't be searched for: it isn't kept")
        model.searchText = "github.com/brauliovc1/secret"
        #expect(model.rows.count == 1, "the linked worktree; the repo folder is its group's header")
        #expect(model.groups.first?.main != nil)

        let environment = fixture.environment()
        let result = try await ProcessRunner.run(
            executable: try CLIBinary.url(),
            arguments: ["scan", "--json", "--no-sizes", "--root", fixture.scanRoot.path],
            environmentAdditions: [
                "BONSAI_SETTINGS_DIR": environment.settingsDirectory.path,
                "CLAUDE_CONFIG_DIR": environment.claudeConfigDirectory.path,
            ],
            timeout: .seconds(120)
        )
        #expect(result.succeeded, "\(result.stderr)")
        let json = result.stdoutString
        #expect(!json.contains(Self.token))
        struct Output: Decodable {
            struct Verdict: Decodable {
                struct Commit: Decodable {
                    var subject: String
                    var author: String
                    var sha: String
                }
                var path: String
                var lastCommit: Commit?
                var remotes: [GitRemote]
            }
            struct Scan: Decodable {
                var lastCommits: [String: CommitSummary]?
            }
            var scan: Scan
            var verdicts: [Verdict]
        }
        let output = try JSONDecoder().decode(Output.self, from: result.stdout)
        #expect(output.verdicts.count == 2)
        #expect(output.verdicts.allSatisfy { $0.lastCommit?.subject == "Initial commit" && $0.lastCommit?.author == "Fixture" })
        #expect(output.verdicts.allSatisfy { $0.remotes.map(\.name) == ["origin", "upstream"] })
        #expect(output.scan.lastCommits == nil, "carried by each verdict, not twice")
    }
}
