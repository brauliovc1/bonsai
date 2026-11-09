@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The package-copy rule in light clean (PLAN §4.1 / §4.2, added 11-09): "Clean dependencies…" works on a Flutter
/// worktree's `build/` holding broken Xcode copies, and still keeps a `build/` holding someone's work.
@Suite("Light clean: package copies")
struct LightCleanPackageCopyTests {
    private func world() async throws -> (LightCleanWorld, URL) {
        let world = try await LightCleanWorld.make()
        try world.fixture.write("build/\n", to: ".git/info/exclude", in: world.repo)
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "flutter")
        try world.file("build/app/outputs/app.apk", in: wt, kibibytes: 64)
        return (world, wt)
    }

    @Test func buildWithBrokenPackageCopiesIsCleaned() async throws {
        let (world, wt) = try await world()
        defer { world.remove() }
        try await world.fixture.xcodePackage("facebook-ios-sdk", in: wt, broken: true)
        try await world.fixture.xcodePackage("GoogleUtilities", in: wt)
        let worktree = try await world.worktree(wt)
        let known = try await world.known()

        let found = await world.finder().candidates(in: worktree, knownWorktrees: known)
        #expect(found.skipped.isEmpty, "\(found)")
        let candidate = try #require(found.candidates.first { $0.relativePath == "build" })
        #expect(candidate.packageClones == [
            "ios/SourcePackages/checkouts/GoogleUtilities", "ios/SourcePackages/checkouts/facebook-ios-sdk",
            "ios/SourcePackages/repositories/GoogleUtilities-1a2b3c4d",
            "ios/SourcePackages/repositories/facebook-ios-sdk-1a2b3c4d",
        ])

        let result = try await world.cleaner().clean(worktree, candidates: [candidate], knownWorktrees: known)
        #expect(result.deleted.map(\.relativePath) == ["build"], "\(result)")
        #expect(!world.exists("build", in: wt))
    }

    @Test func buildHoldingAClonesLocalWorkAtAnotherPathIsKept() async throws {
        let (world, wt) = try await world()
        defer { world.remove() }
        try await world.fixture.xcodePackage("facebook-ios-sdk", in: wt, broken: true)
        let clone = try await world.packageClone(in: wt, at: "build/vendor/mylib")
        try world.fixture.write("my work\n", to: "Draft.swift", in: clone)
        let worktree = try await world.worktree(wt)
        let known = try await world.known()

        let found = await world.finder().candidates(in: worktree, knownWorktrees: known)
        #expect(!found.candidates.contains { $0.relativePath == "build" }, "\(found)")
        #expect(found.skipped.first { $0.relativePath == "build" }?.reason == .nestedCheckout(["vendor/mylib"]))

        // Asked to clean it anyway (a candidate from before the clone appeared), the re-check keeps it.
        let stale = LightCleanCandidate(worktreePath: worktree.path, relativePath: "build", name: "build",
                                        estimatedBytes: nil, packageClones: [])
        let result = try await world.cleaner().clean(worktree, candidates: [stale], knownWorktrees: known)
        #expect(result.deleted.isEmpty)
        #expect(result.refused.map(\.reason) == [.nestedCheckout(["vendor/mylib"])], "\(result)")
        #expect(world.exists("build/vendor/mylib/Draft.swift", in: wt))
    }

    /// P12b review (P0): "Clean dependencies…" keeps a `.build` holding a repo with work inside a package copy.
    @Test func dotBuildHoldingARepoWithWorkInsideACopyIsKept() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("swift-nio", in: wt, base: ".build")
        let mine = try await PackageCopyInsideTests.repoWithWork(world.fixture, in: checkout, at: "vendor/mine")
        let worktree = try await world.worktree(wt)
        let known = try await world.known()

        let found = await world.finder().candidates(in: worktree, knownWorktrees: known)
        #expect(!found.candidates.contains { $0.relativePath == ".build" }, "\(found)")
        #expect(found.skipped.first { $0.relativePath == ".build" }?.reason == .nestedCheckout(["checkouts/swift-nio/vendor/mine"]))
        let stale = LightCleanCandidate(worktreePath: worktree.path, relativePath: ".build", name: ".build",
                                        estimatedBytes: nil, packageClones: [])
        let result = try await world.cleaner().clean(worktree, candidates: [stale], knownWorktrees: known)
        #expect(result.deleted.isEmpty, "\(result)")
        #expect(FileManager.default.fileExists(atPath: mine.appending(path: "work.txt").path))
    }
}
