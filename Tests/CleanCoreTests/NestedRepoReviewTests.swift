@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The wave-3 review's nested-repo findings (r3, r4, r5, r7 and items 4 and 6): "no local work" for a nested
/// clone checks what PLAN §4.1 checks for a worktree, bare repos count, and a nested repo's config is read
/// before git runs there. Light clean and P2's worktree removal share `NestedCloneCheck`.
@Suite("Nested repos: wave-3 review")
struct NestedRepoReviewTests {
    /// A sibling worktree with an ignored `node_modules/ok.js` and the findings for it.
    private func findings(_ world: LightCleanWorld, _ wt: URL) async throws -> LightCleanFindings {
        await world.finder().candidates(in: try await world.worktree(wt), knownWorktrees: try await world.known())
    }

    enum LocalWork: String, CaseIterable {
        case untrackedHiddenByConfig, hiddenEdit, ignoredUserFile, reflogOnlyCommit, operationInProgress
    }

    @Test(arguments: LocalWork.allCases)
    func aCloneWithLocalWorkKeepsTheFolder(_ work: LocalWork) async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "nested")
        let clone = try await world.packageClone(in: wt, at: "node_modules/mylib")
        let fixture = world.fixture
        switch work {
        case .untrackedHiddenByConfig:  // r3
            try await fixture.run(["config", "status.showUntrackedFiles", "no"], in: clone)
            try fixture.write("new work\n", to: "NewModule.swift", in: clone)
        case .hiddenEdit:  // r4
            try await fixture.run(["update-index", "--assume-unchanged", "Package.swift"], in: clone)
            try fixture.write("// my local edit\n", to: "Package.swift", in: clone)
        case .ignoredUserFile:  // r5
            try fixture.write(".env\n", to: ".git/info/exclude", in: clone)
            try fixture.write("SECRET=1\n", to: ".env", in: clone)
        case .reflogOnlyCommit:
            try fixture.write("patch\n", to: "Patch.swift", in: clone)
            try await fixture.commitAll(in: clone, message: "Detached work")
            try await fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: clone)
        case .operationInProgress:
            let head = try await fixture.run(["rev-parse", "HEAD"], in: clone)
            try fixture.write(head + "\n", to: ".git/MERGE_HEAD", in: clone)
        }

        let found = try await findings(world, wt)

        #expect(found.candidates.isEmpty, "\(work): \(found)")
        #expect(found.skipped.map(\.reason) == [.nestedCheckout(["mylib"])], "\(work)")
    }

    // r7: a bare repo holding the only copy of a commit.
    @Test func aBareRepoThatIsNotAMirrorKeepsTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "r7")
        let bare = wt.appending(path: "node_modules/backup.git")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try await world.fixture.run(["init", "--quiet", "--bare", bare.path], in: world.fixture.url)
        try await world.fixture.run(["remote", "add", "backup", bare.path], in: wt)
        try world.fixture.write("only here\n", to: "unique.txt", in: wt)
        try await world.fixture.commitAll(in: wt, message: "unique")
        try await world.fixture.run(["push", "--quiet", "backup", "HEAD:refs/heads/keep"], in: wt)

        let found = try await findings(world, wt)

        #expect(found.candidates.isEmpty, "\(found)")
        #expect(found.skipped.map(\.reason) == [.nestedCheckout(["backup.git"])])
        #expect(NestedCheckoutSearch().search(wt.appending(path: "node_modules")).bareRepos == ["backup.git"])
    }

    // The SwiftPM / Xcode layout: mirrors in repositories/, clones in checkouts/, both with
    // `core.fsmonitor=false` the way those tools write it. All of it is fetched again.
    @Test func packageMirrorsAndClonesDoNotKeepTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "swiftpm")
        let clone = try await world.packageClone(in: wt, at: ".build/checkouts/lib")
        try await world.fixture.run(["config", "core.fsmonitor", "false"], in: clone)
        let remote = try await world.fixture.run(["config", "remote.origin.url"], in: clone)
        let mirror = wt.appending(path: ".build/repositories/lib-1234")
        try await world.fixture.run(["clone", "--quiet", "--mirror", remote, mirror.path], in: world.fixture.url)
        try await world.fixture.run(["config", "--file", mirror.appending(path: "config").path, "core.fsmonitor", "false"], in: world.fixture.url)

        let found = try await findings(world, wt)

        #expect(found.skipped.isEmpty, "\(found)")
        #expect(found.candidates.map(\.relativePath) == [".build"])
        #expect(found.candidates.first?.packageClones == ["checkouts/lib", "repositories/lib-1234"])
    }

    // Item 6: a key that makes git run a command or read another file is local work, and git never runs
    // in that clone (its fsmonitor hook would leave the marker).
    @Test(arguments: ["core.fsmonitor", "filter.lfs.clean", "include.path", "includeIf.gitdir:/.path"])
    func aCloneWhoseConfigCouldRunSomethingKeepsTheFolder(_ key: String) async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "config")
        let clone = try await world.packageClone(in: wt, at: "node_modules/mylib")
        let marker = world.fixture.url.appending(path: "ran")
        let script = try world.fixture.write("#!/bin/sh\ntouch '\(marker.path)'\nexit 1\n", to: "run.sh", in: world.fixture.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        // Includes point at a valid (empty) config file, so only the guard can tell them apart.
        let included = try world.fixture.write("", to: "included.config", in: world.fixture.url)
        try await world.fixture.run(["config", key, key.hasPrefix("include") ? included.path : script.path], in: clone)

        let found = try await findings(world, wt)

        #expect(found.skipped.map(\.reason) == [.nestedCheckout(["mylib"])], "\(key)")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "\(key): something ran")
    }

    @Test func configParsingFindsCommandKeysAndMirrors() {
        let data = Data("core.fsmonitor\nfalse\u{0}remote.up.stream.mirror\ntrue\u{0}remote.up.stream.fetch\n+refs/*:refs/*\u{0}core.bare\u{0}".utf8)
        let config = NestedRepoConfig(entries: NestedRepoConfig.parse(data))
        #expect(config.entries.map(\.key) == ["core.fsmonitor", "remote.up.stream.mirror", "remote.up.stream.fetch", "core.bare"])
        #expect(config.commandKeys.isEmpty)
        #expect(config.isMirror)
        #expect(NestedRepoConfig(entries: [("core.fsmonitor", "true")]).commandKeys == ["core.fsmonitor"])
        #expect(NestedRepoConfig(entries: [("includeif.onbranch:main.path", "x")]).commandKeys.count == 1)
        #expect(!NestedRepoConfig(entries: [("remote.origin.mirror", "true"), ("remote.origin.fetch", "+refs/heads/*:refs/heads/*")]).isMirror)
    }
}
