@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branch tracking and read-only proof", .serialized)
struct BranchTrackingTests {
    @Test func trackingNamesSurviveSanitizationAndReportUnpushedCommits() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "a"], in: world.repo)
        try await world.fixture.run(["checkout", "--quiet", "a"], in: world.repo)
        try await world.commit("not-pushed.txt", date: world.epoch + 40_000)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let a = try await reader.load(branch: "a", base: "main")
        #expect(a.upstream.ref == "refs/remotes/origin/a")
        #expect(a.upstream.ahead == 1 && a.upstream.behind == 0)
        #expect(a.upstream.summary == "1 commit not pushed")
        let main = await reader.upstream("refs/heads/main")
        #expect(main.ref == "refs/remotes/origin/main" && main.summary == "Pushed")
        #expect(await reader.upstream("refs/heads/b").summary == "No upstream")
    }

    @Test func quotedBranchNamesRemainDataInTrackingConfig() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["push", "--quiet", "origin", "a"], in: world.repo)
        let name = "odd/\"branch"
        try await world.fixture.run(["branch", name, "a"], in: world.repo)
        try await world.fixture.run(["branch", "--set-upstream-to=origin/a", name], in: world.repo)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let result = await BranchLineageReader(git: git, catalog: catalog).upstream("refs/heads/" + name)
        #expect(result.ref == "refs/remotes/origin/a" && result.summary == "Pushed")
        #expect(result.problem == nil)
    }

    @Test func includesAndExecutableConfigNeverCrossTheGitBoundary() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let marker = world.fixture.url.appending(path: "should-not-run")
        let include = world.fixture.url.appending(path: "include.config")
        let command = "touch \(marker.path)"
        try Data("[core]\nfsmonitor = \(command)\n".utf8).write(to: include)
        for (key, value) in [("core.fsmonitor", command), ("diff.external", command), ("merge.bad.driver", command), ("include.path", include.path)] {
            try await world.fixture.run(["config", "--local", key, value], in: world.repo)
        }
        let before = try GitMetadataSnapshot(directory: world.repo.appending(path: ".git"))
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let config = try String(contentsOf: git.metadata.appending(path: "config"), encoding: .utf8)
        #expect(!config.contains(command) && !config.contains(include.path))
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.upstream.problem?.contains("included config") == true)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(try GitMetadataSnapshot(directory: world.repo.appending(path: ".git")) == before)
    }

    @Test func mapFamilyAndHistoryLeaveEveryGitMetadataByteUnchanged() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["merge", "--quiet", "--no-ff", "a", "-m", "Merge a for proof"], in: world.repo)
        let folder = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: folder)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let map = BranchMap()
        _ = try await map.load(base: "main", catalog: catalog, includeRemotes: true, using: git)
        #expect(try GitMetadataSnapshot(directory: folder) == before)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        _ = try await reader.family(base: "main")
        #expect(try GitMetadataSnapshot(directory: folder) == before)
        _ = try await reader.load(branch: "a", base: "main")
        #expect(try GitMetadataSnapshot(directory: folder) == before)
        _ = try await reader.load(branch: "b", base: "main")
        #expect(try GitMetadataSnapshot(directory: folder) == before)
    }

    @Test func configParserHandlesCommentsEscapesAndContinuationsWithoutInventingKeys() throws {
        let home = try TemporaryDirectory(prefix: "bonsai-branch-config")
        defer { home.remove() }
        let text = """
        [branch "odd/\\\"name"]
        remote = "ori#gin" # ignored comment
        merge = refs/heads/main
        [remote "ori#gin"]
        fetch = +refs/heads/*:refs/remotes/origin/*
        url = ext::arbitrary-command
        [include]
        path = /untrusted/file
        [core]
        fsmonitor = arbitrary-command
        """
        try Data(text.utf8).write(to: home.url.appending(path: "config"))
        let safe = BranchTrackingConfig.sanitized(common: home.url, worktree: home.url)
        let entries = BranchTrackingConfig.parse(safe)
        #expect(entries.count == 3)
        #expect(entries.contains { $0.section == "branch" && $0.subsection == "odd/\"name" && $0.key == "remote" && $0.value == "ori#gin" })
        #expect(!safe.contains("arbitrary-command") && !safe.contains("untrusted"))
        #expect(BranchTrackingConfig.hasIncludes(common: home.url, worktree: home.url))
        let continued = BranchTrackingConfig.parse("[branch \"a\"]\nremote = ori\\\ngin\n")
        #expect(continued.first?.value == "origin")
    }
}
