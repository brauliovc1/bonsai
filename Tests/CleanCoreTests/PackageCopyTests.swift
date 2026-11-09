@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.1 "Package copies" (added 11-09, P12b): Xcode's and SwiftPM's copies inside an ignored build folder
/// are build output, broken ones included, decided without running git in them. Every other nested repo keeps
/// today's rule, and one git can't read is "couldn't read", not local work.
@Suite("Package copies")
struct PackageCopyTests {
    /// A worktree of a repo whose `build/` is ignored (through `.git/info/exclude`, shared by its worktrees).
    private func flutterLike(_ world: SafetyWorld, _ name: String = "flutter") async throws -> URL {
        try world.fixture.write("build/\n", to: ".git/info/exclude", in: world.repo)
        return try await world.sibling(name)
    }

    private func brokenGitFails(_ world: SafetyWorld, _ checkout: URL) async {
        let status = try? await world.fixture.git.result(["status", "--porcelain"], in: checkout)
        #expect(status?.succeeded == false, "the fixture's copy must be broken")
    }

    @Test func brokenXcodeCopiesInAnIgnoredBuildFolderAreBuildOutput() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await flutterLike(world)
        let good = try await world.fixture.xcodePackage("GoogleUtilities", in: wt)
        let broken = try await world.fixture.xcodePackage("facebook-ios-sdk", in: wt, broken: true)
        await brokenGitFails(world, broken.checkout)
        let spy = try SpyGit(fixture: world.fixture)
        let worktree = try await world.worktree(wt)
        let known = try await WorktreeScanner(git: world.fixture.git, cursorWorktreesDirectory: world.fixture.environment()
            .cursorWorktreesDirectory).worktrees(in: world.repo)

        let check = SafetyCheck(git: spy.git)
        let state = await check.state(of: worktree, knownWorktrees: known)
        let report = SafetyCheck.evaluate(worktree: worktree, state: state, idle: .idle(days: 40), settings: Settings(),
                                          cwdIndex: ProcessCwdIndex(entries: []))

        let base = "build/ios/SourcePackages"
        let copies = ["\(base)/checkouts/GoogleUtilities", "\(base)/checkouts/facebook-ios-sdk",
                      "\(base)/repositories/GoogleUtilities-1a2b3c4d", "\(base)/repositories/facebook-ios-sdk-1a2b3c4d"]
        #expect(report.blockers.isEmpty, "\(report)")
        #expect(report.notes == [.packageCopies(copies.sorted())])
        #expect(report.status == .autoReady)
        #expect(state.nestedUnreadable.isEmpty && state.nestedLocalWork.isEmpty && state.nestedClones.isEmpty)
        // Decided from the path and git's checks on build/, asked from outside: git never ran in a copy, nor read
        // a copy's config.
        let touched = spy.touchedPaths()
        #expect(touched.contains { $0.hasPrefix(CanonicalPath.resolve(wt)) }, "the spy saw git's calls: \(touched)")
        for copy in [good.checkout, good.mirror, broken.checkout, broken.mirror] {
            // git names folders by their real path (/private/var/...); the fixture by /var/....
            let forms = [copy.path, "/private" + copy.path, CanonicalPath.resolve(copy)]
            let inside = touched.filter { path in forms.contains { path.hasPrefix($0) } }
            #expect(inside.isEmpty, "git was given \(inside)")
        }
    }

    @Test func swiftPMCopiesInAnIgnoredDotBuildAreBuildOutput() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        try await world.fixture.xcodePackage("swift-nio", in: wt, base: ".build", broken: true)
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty, "\(report)")
        #expect(report.notes == [.packageCopies([".build/checkouts/swift-nio", ".build/repositories/swift-nio-1a2b3c4d"])])
    }

    enum Elsewhere: String, CaseIterable {
        /// Not a package manager's path.
        case vendorFolder
        /// SourcePackages inside a build folder git tracks a file in.
        case trackedBuildFolder
        /// The same, the tracked file named in another case (`Build/config.txt`; APFS is case-insensitive).
        case trackedInAnotherCase
        /// SourcePackages inside a build folder git doesn't ignore.
        case notIgnored
        /// SourcePackages with no §4.2 folder above it.
        case noBuildFolder
    }

    /// The same broken checkout anywhere else stays blocked, as "couldn't read" with git's message.
    @Test(arguments: Elsewhere.allCases)
    func theSameBrokenCopyElsewhereIsCouldNotRead(_ place: Elsewhere) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let base: String
        switch place {
        case .vendorFolder:
            base = "node_modules/vendor"
        case .trackedBuildFolder:
            try world.fixture.write("build/\n", to: ".git/info/exclude", in: world.repo)
            try world.fixture.write("keep\n", to: "build/README.txt", in: world.repo)
            try await world.fixture.run(["add", "--force", "build/README.txt"], in: world.repo)
            try await world.fixture.run(["commit", "--quiet", "-m", "Track a build file"], in: world.repo)
            try await world.fixture.run(["push", "--quiet", "origin", "main"], in: world.repo)
            base = "build/ios/SourcePackages"
        case .notIgnored:
            base = "build/ios/SourcePackages"
        case .trackedInAnotherCase:
            try world.fixture.write("build/\n", to: ".git/info/exclude", in: world.repo)
            base = "build/ios/SourcePackages"
        case .noBuildFolder:
            try world.fixture.write("SourcePackages/\n", to: ".git/info/exclude", in: world.repo)
            base = "SourcePackages"
        }
        let wt = try await world.sibling("elsewhere")
        if place == .trackedInAnotherCase {
            // git's ignore check alone says "ignored" here; only `ls-files :(icase)build` sees the tracked file.
            try world.fixture.write("v1\n", to: "build/config.txt", in: wt)
            try await world.fixture.run(["add", "-f", "build/config.txt"], in: wt)
            try await world.fixture.run(["mv", "build/config.txt", "Build/config.txt"], in: wt)
            try await world.fixture.run(["commit", "--quiet", "-m", "Track Build/config.txt"], in: wt)
            try #require(FileManager.default.fileExists(atPath: wt.appending(path: "build/config.txt").path))
        }
        let (checkout, _) = try await world.fixture.xcodePackage("firebase-ios-sdk", in: wt, base: base, broken: true)
        await brokenGitFails(world, checkout)

        let report = try await world.check(wt)
        let unreadable = report.blockers.compactMap { reason -> [NestedRepo]? in
            if case .nestedUnreadable(let repos) = reason { return repos }
            return nil
        }.first ?? []
        #expect(unreadable.map(\.path) == ["\(base)/checkouts/firebase-ios-sdk"], "\(place): \(report)")
        #expect(unreadable.first?.findings == ["fatal: bad object HEAD"], "\(place): git's first error line")
        #expect(!report.notes.contains { if case .packageCopies = $0 { true } else { false } }, "\(place)")
        #expect(!report.manualAllowed && !report.autoEligible)
        #expect(!report.blockers.contains { if case .nestedCheckouts = $0 { true } else { false } },
                "\(place): unreadable is not 'contains other repos'")
    }

    /// The rule reads only the path's shape; the git checks decide the rest.
    @Test func outputFoldersFollowThePathShape() {
        #expect(PackageCopyRule.outputFolders(for: "build/ios/SourcePackages/checkouts/x") == ["build"])
        #expect(PackageCopyRule.outputFolders(for: "app/build/DerivedData/SourcePackages/repositories/x-1")
            == ["app/build", "app/build/DerivedData"])
        #expect(PackageCopyRule.outputFolders(for: ".build/checkouts/x") == [".build"])
        #expect(PackageCopyRule.outputFolders(for: "pkg/.build/repositories/x-1") == ["pkg/.build"])
        #expect(PackageCopyRule.outputFolders(for: "SourcePackages/checkouts/x").isEmpty)
        #expect(PackageCopyRule.outputFolders(for: "build/SourcePackages/checkouts/x/y").isEmpty)
        #expect(PackageCopyRule.outputFolders(for: "build/SourcePackages/artifacts/x").isEmpty)
        #expect(PackageCopyRule.outputFolders(for: "build/vendor/checkouts/x").isEmpty)
        #expect(PackageCopyRule.outputFolders(for: ".venv/src/x").isEmpty)
    }

    @Test func aRegisteredWorktreeAtAPackagePathStillBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("outer")
        try await world.fixture.addWorktree(to: world.repo, at: wt.appending(path: ".build/checkouts/inner"), branch: "inner")
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/inner"])], "\(report)")
    }
}
