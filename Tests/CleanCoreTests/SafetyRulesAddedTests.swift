@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The §4.1 rows added on 11-06 (review items 1, 3, 4 and 7).
@Suite("Safety rules added 11-06")
struct SafetyRulesAddedTests {
    // Item 1: assume-unchanged / skip-worktree edits never show in git status.
    @Test func hiddenLocalEditsBlockBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let assumed = try await world.sibling("assumed")
        try await world.fixture.run(["update-index", "--assume-unchanged", "README.md"], in: assumed)
        try world.fixture.write("edited\n", to: "README.md", in: assumed)
        #expect(try await world.fixture.run(["status", "--porcelain"], in: assumed).isEmpty)
        let report = try await world.check(assumed)
        #expect(report.blockers == [.hiddenLocalEdits(["README.md"])])
        #expect(!report.manualAllowed && !report.autoEligible)

        let skipped = try await world.sibling("skipped")
        try await world.fixture.run(["update-index", "--skip-worktree", ".gitignore"], in: skipped)
        try world.fixture.write("edited\n", to: ".gitignore", in: skipped)
        #expect(try await world.check(skipped).blockers == [.hiddenLocalEdits([".gitignore"])])

        // Sparse checkout: a skip-worktree file that isn't on disk holds nothing.
        let sparse = try await world.sibling("sparse")
        try await world.fixture.run(["update-index", "--skip-worktree", "README.md"], in: sparse)
        try FileManager.default.removeItem(at: sparse.appending(path: "README.md"))
        let sparseReport = try await world.check(sparse)
        #expect(sparseReport.manualAllowed && sparseReport.autoEligible, "\(sparseReport)")
    }

    // Item 3: `pip install -e git+...` clones into .venv/src; the search must look inside §4.2 folders. This
    // clone has a remote but an unpushed commit, so it is local work.
    @Test func cloneInsideVenvBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("py")
        let package = try await world.fixture.makeRepo("mypkg", in: world.fixture.url.appending(path: "upstream"))
        let clone = wt.appending(path: ".venv/src/mypkg")
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await world.fixture.run(["clone", "--quiet", package.path, clone.path], in: world.fixture.url)
        try world.fixture.write("unpushed\n", to: "mod.py", in: clone)
        try await world.fixture.commitAll(in: clone, message: "Local only")

        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".venv/src/mypkg"])], "\(report)")
        #expect(!report.manualAllowed && !report.autoEligible)

        // Without a remote at all (`git init` inside .venv), it blocks too.
        let bare = wt.appending(path: ".venv/src/scratch")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try await world.fixture.run(["init", "--quiet"], in: bare)
        try world.fixture.write("x\n", to: "x.py", in: bare)
        try await world.fixture.commitAll(in: bare)
        #expect(try await world.check(wt).blockers == [.nestedCheckouts([".venv/src/mypkg", ".venv/src/scratch"])])
    }

    // Item 3: a capped or unreadable search can't promise there is nothing inside.
    @Test func incompleteNestedSearchIsANoteForManualAndBlocksAuto() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("deep")
        for index in 0..<5 {
            try world.fixture.write("x\n", to: "node_modules/pkg\(index)/index.js", in: wt)
        }
        let capped = try await world.check(wt, nestedSearch: NestedCheckoutSearch(limit: 4))
        #expect(capped.notes == [.nestedSearchIncomplete("stopped after 4 entries")])
        #expect(capped.manualAllowed && !capped.autoEligible)

        let locked = wt.appending(path: "node_modules/pkg3")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let unreadable = try await world.check(wt)
        #expect(unreadable.notes == [.nestedSearchIncomplete("cannot read node_modules/pkg3")], "\(unreadable)")
        #expect(unreadable.manualAllowed && !unreadable.autoEligible)
    }

    @Test func nestedSearchSkipsSymlinksAndFindsDeepCheckouts() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let root = fixture.url.appending(path: "wt")
        try fixture.write("gitdir: x\n", to: ".git", in: root)
        try fixture.write("x\n", to: "node_modules/a/b/c/.git/HEAD", in: root)
        try fixture.write("x\n", to: "node_modules/a/b/c/inner/.git", in: root)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: fixture.home)
        try fixture.write("x\n", to: ".git", in: fixture.home)
        try fixture.write("gitdir: x\n", to: "vendor/linked/.git", in: root)
        let result = NestedCheckoutSearch().search(root)
        #expect(result.checkouts == ["node_modules/a/b/c", "vendor/linked"])
        #expect(result.gitFiles == ["vendor/linked"])
        #expect(result.incomplete == nil)
    }

    // Item 4: commit while detached, then move HEAD away: only this worktree's reflog still names it.
    @Test func detachedReflogOnlyCommitsBlockBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addWorktree(to: world.repo, at: world.fixture.url.appending(path: "det"), detached: true)
        try world.fixture.write("work\n", to: "work.txt", in: wt)
        try await world.fixture.commitAll(in: wt)
        try await world.fixture.run(["checkout", "--quiet", "--detach", "origin/main"], in: wt)
        #expect(try await world.fixture.run(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: wt) == "0")

        let report = try await world.check(wt)
        #expect(report.blockers == [.reflogOnlyCommits(count: 1)])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    // Item 4: a half-done rebase, merge, cherry-pick, revert or bisect.
    @Test func operationInProgressBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let bisecting = try await world.sibling("bisecting")
        try await world.fixture.run(["bisect", "start"], in: bisecting)
        let report = try await world.check(bisecting)
        #expect(report.blockers == [.operationInProgress(["BISECT_LOG"])])
        #expect(!report.manualAllowed && !report.autoEligible)
        #expect(report.status.label == "BLOCKED: bisect in progress")

        let merging = try await world.sibling("merging")
        let gitDir = URL(fileURLWithPath: try await world.fixture.run(["rev-parse", "--absolute-git-dir"], in: merging))
        let head = try await world.fixture.run(["rev-parse", "HEAD"], in: merging)
        try world.fixture.write(head + "\n", to: "MERGE_HEAD", in: gitDir)
        #expect(try await world.check(merging).blockers == [.operationInProgress(["MERGE_HEAD"])])
    }

    // Item 7: ruff, pytest and mypy caches ignore themselves, so git lists their files one by one.
    @Test func selfIgnoringCacheFoldersAreBuildOutput() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("caches")
        for cache in [".ruff_cache", "src/.pytest_cache", ".mypy_cache"] {
            try world.fixture.write("*\n", to: "\(cache)/.gitignore", in: wt)
            try world.fixture.write("x\n", to: "\(cache)/0.1/data/file", in: wt)
            try world.fixture.write("x\n", to: "\(cache)/CACHEDIR.TAG", in: wt)
        }
        let report = try await world.check(wt)
        #expect(report.notes.isEmpty, "\(report)")
        #expect(report.autoEligible)

        // A §4.2-named folder git tracks files in is not output: its ignored files are still user files.
        let tracked = try await world.sibling("tracked-build")
        try world.fixture.write("docs\n", to: "build/README.md", in: tracked)
        try world.fixture.write("*.secret\n", to: "build/.gitignore", in: tracked)
        try await world.fixture.commitAll(in: tracked)
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "tracked-build"], in: tracked)
        try world.fixture.write("key\n", to: "build/api.secret", in: tracked)
        let trackedReport = try await world.check(tracked)
        #expect(trackedReport.notes == [.ignoredUserFiles(["build/api.secret"])], "\(trackedReport)")
        #expect(trackedReport.manualAllowed && !trackedReport.autoEligible)
    }
}
