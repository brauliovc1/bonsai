@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Nested clones with no local work count like §4.2 build output (PLAN §4.1 "Nested checkouts", 11-06).
@Suite("Nested clones")
struct NestedCloneTests {
    /// A package clone the way SwiftPM leaves it: cloned from a bare remote into `<worktree>/<relative>`,
    /// detached at a pushed tag.
    @discardableResult
    private func packageClone(_ world: SafetyWorld, in worktree: URL, at relative: String) async throws -> URL {
        let fixture = world.fixture
        let id = UUID().uuidString.prefix(8)
        let remote = fixture.remotes.appending(path: "pkg-\(id).git")
        try await fixture.run(["init", "--quiet", "--bare", remote.path], in: fixture.url)
        let seed = fixture.url.appending(path: "seed-\(id)")
        try await fixture.run(["clone", "--quiet", remote.path, seed.path], in: fixture.url)
        try fixture.write("// package\n", to: "Package.swift", in: seed)
        try await fixture.commitAll(in: seed, message: "Release")
        try await fixture.run(["tag", "1.0.0"], in: seed)
        try await fixture.run(["push", "--quiet", "origin", "main", "--tags"], in: seed)

        let clone = worktree.appending(path: relative)
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await fixture.run(["clone", "--quiet", remote.path, clone.path], in: fixture.url)
        try await fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: clone)
        return clone
    }

    @Test func cleanPackageClonesAreANoteOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let names = ["swift-argument-parser", "swift-collections", "swift-log", "swift-nio", "swift-syntax"]
        for name in names {
            try await packageClone(world, in: wt, at: ".build/checkouts/\(name)")
        }
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty, "\(report)")
        #expect(report.notes == [.nestedClones(names.map { ".build/checkouts/\($0)" })])
        #expect(report.manualAllowed && report.autoEligible)
        #expect(report.status == .autoReady)
    }

    enum LocalWork: String, CaseIterable {
        case unpushedCommit, unpushedBranch, dirtyFile, stash, noRemote
    }

    @Test(arguments: LocalWork.allCases)
    func cloneWithLocalWorkBlocksBoth(_ work: LocalWork) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let clone = try await packageClone(world, in: wt, at: ".build/checkouts/pkg")
        switch work {
        case .unpushedCommit:
            try world.fixture.write("patch\n", to: "Patch.swift", in: clone)
            try await world.fixture.commitAll(in: clone, message: "Local patch")
        case .unpushedBranch:
            try await world.fixture.run(["checkout", "--quiet", "-b", "local"], in: clone)
            try world.fixture.write("patch\n", to: "Patch.swift", in: clone)
            try await world.fixture.commitAll(in: clone, message: "Local patch")
            try await world.fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: clone)
        case .dirtyFile:
            try world.fixture.write("draft\n", to: "Draft.swift", in: clone)
        case .stash:
            try world.fixture.write("edited\n", to: "Package.swift", in: clone)
            try await world.fixture.run(["stash", "push", "--quiet"], in: clone)
        case .noRemote:
            try await world.fixture.run(["remote", "remove", "origin"], in: clone)
        }
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/pkg"])], "\(work): \(report)")
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func brokenGitFolderOrGitFileBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("odd")
        // An empty `.git` folder isn't a repo: git would answer for the worktree around it.
        try FileManager.default.createDirectory(at: wt.appending(path: ".build/checkouts/broken/.git"), withIntermediateDirectories: true)
        // A `.git` file is a linked worktree or submodule of some repo, never a plain clone: here a clean
        // worktree of a repo outside the scan (so it isn't in the registered list either).
        let outside = try await world.fixture.makeRepo("outside", in: world.fixture.url.appending(path: "elsewhere"))
        try await world.fixture.addWorktree(to: outside, at: wt.appending(path: ".build/checkouts/linked"), branch: "linked")
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "linked"], in: wt.appending(path: ".build/checkouts/linked"))
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/broken", ".build/checkouts/linked"])], "\(report)")
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func registeredWorktreeInAPackageFolderStillBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("outer")
        try await packageClone(world, in: wt, at: ".build/checkouts/pkg")
        try await world.fixture.addWorktree(to: world.repo, at: wt.appending(path: ".build/checkouts/registered"), branch: "registered")
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/registered"])], "\(report)")
        #expect(report.notes == [.nestedClones([".build/checkouts/pkg"])])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func swiftPMBuildFolderIsRegenerable() {
        #expect(RegenerableNames.isRegenerableFolder(".build"))
        #expect(RegenerableNames.isHarmlessIgnoredPath(".build/"))
        #expect(RegenerableNames.isHarmlessIgnoredPath("Packages/Core/.build/"))
    }
}
