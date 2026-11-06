@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Light clean never deletes another checkout's work (wave-2 review item A), and works on paths that are
/// not plain ASCII (item B).
@Suite("Light clean: nested checkouts and non-ASCII paths")
struct LightCleanNestedTests {
    @Test func cleanPackageClonesDoNotStopTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "swiftpm")
        try await world.packageClone(in: wt, at: ".build/checkouts/swift-log")
        try await world.packageClone(in: wt, at: ".build/checkouts/swift-nio")

        let findings = await world.finder().candidates(in: try await world.worktree(wt), knownWorktrees: try await world.known())

        let candidate = try #require(findings.candidates.first)
        #expect(findings.candidates.count == 1 && findings.skipped.isEmpty, "\(findings)")
        #expect(candidate.relativePath == ".build")
        #expect(candidate.packageClones == ["checkouts/swift-log", "checkouts/swift-nio"])
    }

    enum NestedKind: String, CaseIterable {
        case cloneWithCommit, cloneWithDirtyFile, cloneWithoutRemote, gitFile, registeredWorktree, folderIsAClone
    }

    @Test(arguments: NestedKind.allCases)
    func anotherCheckoutInsideKeepsTheFolder(_ kind: NestedKind) async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "nested")
        try world.file("node_modules/ok/index.js", in: wt)
        try world.file("packages/a/node_modules/x.js", in: wt)
        let folder = wt.appending(path: "packages/a/node_modules")
        var expected = ["inner"]
        switch kind {
        case .cloneWithCommit:
            let clone = try await world.packageClone(in: folder, at: "inner")
            try world.fixture.write("patch\n", to: "Patch.swift", in: clone)
            try await world.fixture.commitAll(in: clone, message: "Local patch")
        case .cloneWithDirtyFile:
            let clone = try await world.packageClone(in: folder, at: "inner")
            try world.fixture.write("draft\n", to: "Draft.swift", in: clone)
        case .cloneWithoutRemote:
            let clone = try await world.packageClone(in: folder, at: "inner")
            try await world.fixture.run(["remote", "remove", "origin"], in: clone)
        case .gitFile:
            // A clean worktree of a repo outside the scan: its `.git` file is enough.
            let outside = try await world.fixture.makeRepo("outside", in: world.fixture.url.appending(path: "elsewhere"))
            try await world.fixture.addWorktree(to: outside, at: folder.appending(path: "inner"), branch: "inner")
        case .registeredWorktree:
            try await world.fixture.addWorktree(to: world.repo, at: folder.appending(path: "inner"), branch: "inner")
        case .folderIsAClone:
            try FileManager.default.removeItem(at: folder)
            try await world.packageClone(in: wt.appending(path: "packages/a"), at: "node_modules")
            expected = ["."]
        }

        let findings = await world.finder().candidates(in: try await world.worktree(wt), knownWorktrees: try await world.known())

        #expect(findings.candidates.map(\.relativePath) == ["node_modules"], "\(kind)")
        #expect(findings.skipped == [
            LightCleanSkip(relativePath: "packages/a/node_modules", name: "node_modules", reason: .nestedCheckout(expected)),
        ], "\(kind)")
    }

    @Test func aRegisteredWorktreeHiddenFromTheWalkStillKeepsTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let beta = try await world.fixture.makeRepo("beta")
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "outer")
        let hidden = wt.appending(path: "node_modules/cache")
        try await world.fixture.addWorktree(to: beta, at: hidden.appending(path: "inner"), branch: "inner")
        let known = try await world.known([world.repo, beta])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hidden.path) }

        let findings = await world.finder().candidates(in: try await world.worktree(wt), knownWorktrees: known)

        #expect(findings.candidates.isEmpty)
        #expect(findings.skipped.map(\.reason) == [.nestedCheckout(["cache/inner"])])
    }

    @Test func aSearchThatCannotFinishKeepsTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "capped")
        for index in 0..<5 { try world.file("node_modules/p\(index).js", in: wt) }

        let capped = world.finder(nestedSearch: NestedCheckoutSearch(limit: 3))
        let findings = await capped.candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.isEmpty)
        #expect(findings.skipped.map(\.reason) == [.nestedSearchIncomplete("stopped after 3 entries")])
    }

    // Item B: Foundation's Process decomposes arguments, and git can't recompose an emoji path, so git must
    // run inside the folder with "." rather than get the folder's path.
    @Test(arguments: [false, true])
    func aComposedEmojiWorktreeIsFoundAndCleaned(precompose: Bool) async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        try await world.fixture.run(["config", "core.precomposeunicode", "\(precompose)"], in: world.repo)
        // Registered composed, as a shell or the Claude app would: mkdir with exact bytes, git add from inside.
        let composed = world.repo.path + "/.claude/worktrees/wt \u{1F680} caf\u{E9}"
        try FileManager.default.createDirectory(at: world.repo.appending(path: ".claude/worktrees"), withIntermediateDirectories: true)
        #expect(mkdir(composed, 0o755) == 0)
        let wt = URL(fileURLWithPath: composed)
        try await world.fixture.run(["worktree", "add", "--quiet", "-b", "cafe", "."], in: wt)
        try world.file("node_modules/x.js", in: wt)
        try world.file("packages/caf\u{E9}/node_modules/y.js", in: wt)
        let worktree = try await world.worktree(wt)
        #expect(worktree.path.utf8.reversed().starts(with: " caf\u{E9}".utf8.reversed()), "registered composed")

        let findings = await world.finder().candidates(in: worktree, knownWorktrees: try await world.known())
        #expect(findings.skipped.isEmpty, "\(findings.skipped)")
        #expect(findings.candidates.map(\.relativePath) == ["node_modules", "packages/caf\u{E9}/node_modules"])
        #expect(findings.candidates.allSatisfy { $0.estimatedBytes == Int64(4 * 1024) })

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)
        #expect(result.deleted.count == 2 && result.refused.isEmpty && result.failed.isEmpty, "\(result)")
        #expect(!world.exists("node_modules", in: wt))
        #expect(!world.exists("packages/caf\u{E9}/node_modules", in: wt))
        #expect(world.exists("packages/caf\u{E9}", in: wt))
        #expect(try world.log.entries().map(\.action) == [.lightClean, .lightClean])
    }
}
