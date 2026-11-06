@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Paths outside plain ASCII (review items 2 and 8).
@Suite("Non-ASCII paths")
struct PathEncodingTests {
    // Item 2: lsof prints bytes >= 0x80 as \xNN.
    @Test func processInsideANonASCIIFolderIsFound() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addWorktree(
            to: world.repo,
            at: world.fixture.scanRoot.appending(path: "wt-\u{65E5}\u{672C}"),
            branch: "nihon"
        )
        let sleeper = SleepingProcess()
        defer { sleeper.stop() }
        try sleeper.start(in: wt)

        let index = await ProcessCwdIndex.capture(lsof: world.fixture.environment().tools.lsof)
        try #require(index.isAvailable)
        #expect(index.processes(inside: wt).map(\.pid) == [try #require(sleeper.pid)])
        let report = try await world.check(wt, cwdIndex: index)
        #expect(report.status == .inUse)
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func lsofEscapesAreDecoded() {
        let output = #"""
        p1
        cvim
        fcwd
        n/w/wt-\xe6\x97\xa5\xe6\x9c\xac
        p2
        cbash
        fcwd
        n/w/back\\slash\tx
        p3
        csh
        fcwd
        n/w/caret^Ax
        p4
        cls
        fcwd
        n/w/lit\\x41
        """#
        let entries = ProcessCwdIndex.parse(Data(output.utf8))
        #expect(entries.map(\.cwd) == ["/w/wt-\u{65E5}\u{672C}", "/w/back\\slash\tx", "/w/caret^Ax", "/w/lit\\x41"])
        #expect(entries[2].alternativeCwds == ["/w/caret\u{01}x"])
        let index = ProcessCwdIndex(entries: entries)
        #expect(index.processes(inside: URL(fileURLWithPath: "/w/wt-\u{65E5}\u{672C}")).map(\.pid) == [1])
        #expect(index.processes(inside: URL(fileURLWithPath: "/w/caret\u{01}x")).map(\.pid) == [3])
        #expect(index.processes(inside: URL(fileURLWithPath: "/w/caret^Ax")).map(\.pid) == [3])
        // Composed and decomposed "é" are the same folder.
        let composed = ProcessCwdIndex(entries: [.init(pid: 5, command: "x", cwd: "/w/caf\u{E9}/src")])
        #expect(composed.processes(inside: URL(fileURLWithPath: "/w/cafe\u{301}")).map(\.pid) == [5])
    }

    // Item 8: Process hands git decomposed arguments, and git can't recompose a path with an emoji, so
    // `git -C <repo> worktree remove <path>` can't find "wt 🚀 café" registered composed.
    @Test(arguments: [false, true])
    func composedEmojiPathIsRemovedAndRestored(precompose: Bool) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        try await world.fixture.run(["config", "core.precomposeunicode", "\(precompose)"], in: world.repo)
        // Register it composed, as a shell or the Claude app would: create the folder with exact bytes
        // (mkdir, not FileManager, which decomposes) and let git read its name from inside.
        let composed = world.repo.path + "/.claude/worktrees/wt \u{1F680} caf\u{E9}"
        try FileManager.default.createDirectory(at: world.repo.appending(path: ".claude/worktrees"), withIntermediateDirectories: true)
        #expect(mkdir(composed, 0o755) == 0)
        try await world.fixture.run(["worktree", "add", "--quiet", "-b", "cafe", "."], in: URL(fileURLWithPath: composed))
        let listing = try await world.fixture.git.git(["worktree", "list", "--porcelain", "-z"], in: world.repo)
        let registered = try #require(WorktreeListParser.parse(listing).first { $0.branch == "cafe" })
        #expect(registered.path.utf8.reversed().starts(with: " caf\u{E9}".utf8.reversed()), "registered composed")
        let worktree = try await world.worktree(URL(fileURLWithPath: composed))
        #expect(Array(worktree.path.utf8) == Array(registered.path.utf8))
        #expect(try await world.check(URL(fileURLWithPath: composed)).manualAllowed)

        let remover = Remover(git: world.fixture.git, settings: Settings(), environment: world.fixture.environment())
        let result = try await remover.remove(worktree, mode: .manual, estimatedBytes: nil)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        #expect(!FileManager.default.fileExists(atPath: composed))
        #expect(Array(result.entry.path.utf8) == Array(registered.path.utf8))

        _ = try await Restorer(git: world.fixture.git, environment: world.fixture.environment())
            .restore(entryID: result.entry.id)
        #expect(try await world.fixture.run(["rev-parse", "--abbrev-ref", "HEAD"], in: URL(fileURLWithPath: composed)) == "cafe")
    }

    @Test func decomposedRegistrationsAreMatchedToo() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        try await world.fixture.run(["config", "core.precomposeunicode", "false"], in: world.repo)
        let decomposed = world.fixture.scanRoot.path + "/wt \u{1F680} cafe\u{301}"
        try await world.fixture.run(["worktree", "add", "--quiet", "-b", "nfd", decomposed], in: world.repo)
        let worktree = try await world.worktree(URL(fileURLWithPath: decomposed))
        #expect(worktree.path.utf8.reversed().starts(with: " cafe\u{301}".utf8.reversed()), "registered decomposed")
        let remover = Remover(git: world.fixture.git, settings: Settings(), environment: world.fixture.environment())
        _ = try await remover.remove(worktree, mode: .manual, estimatedBytes: nil)
        #expect(!FileManager.default.fileExists(atPath: decomposed))
    }

    @Test func unicodeOptionsFollowThePathsForm() {
        #expect(Git.unicodeOptions(forPath: "/a/plain") == [])
        #expect(Git.unicodeOptions(forPath: "/a/caf\u{E9}") == ["-c", "core.precomposeunicode=true"])
        #expect(Git.unicodeOptions(forPath: "/a/cafe\u{301}") == ["-c", "core.precomposeunicode=false"])
    }

    @Test func standardizeKeepsCharactersAndRemovesDots() {
        #expect(Array(Worktree.standardize("/a/caf\u{E9}").utf8) == Array("/a/caf\u{E9}".utf8))
        #expect(Worktree.standardize("/a/./b//c/../d/") == "/a/b/d")
        #expect(Worktree.standardize("/..") == "/")
    }
}
