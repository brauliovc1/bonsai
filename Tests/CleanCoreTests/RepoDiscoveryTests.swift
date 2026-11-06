import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Discovery only looks at the file system, so these fixtures fake repos with bare `.git` folders.
@Suite("RepoDiscovery")
struct RepoDiscoveryTests {
    private let fileManager = FileManager.default

    @discardableResult
    private func folder(_ base: URL, _ relative: String) throws -> URL {
        let url = base.appending(path: relative, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fake main repo: a folder with a `.git` directory.
    @discardableResult
    private func repo(_ base: URL, _ relative: String) throws -> URL {
        let url = try folder(base, relative)
        try folder(url, ".git")
        return url
    }

    private func names(_ result: DiscoveryResult, relativeTo base: URL) -> [String] {
        result.repos.map { CanonicalPath.relativePath(of: $0, to: base) ?? $0.path }
    }

    @Test func rootThatIsARepoCounts() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let root = try repo(temp.url, "solo")
        try repo(root, "vendor/nested")  // inside a repo: not descended into

        let result = RepoDiscovery().discover(roots: [root])
        #expect(result.repos.map(\.path) == [root.path])
        #expect(result.issues.isEmpty)
    }

    @Test func findsReposToDepthThreeOnly() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let root = try folder(temp.url, "root")
        try repo(root, "d1")
        try repo(root, "d1/inner")  // inside d1: skipped
        try repo(root, "a/d2")
        try repo(root, "a/b/d3")
        try repo(root, "a/b/c/d4")  // depth 4: not found

        let result = RepoDiscovery().discover(roots: [root])
        #expect(names(result, relativeTo: root) == ["a/b/d3", "a/d2", "d1"])
    }

    @Test func skipsWorktreesDependencyHiddenSymlinkedAndBareFolders() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let root = try folder(temp.url, "root")
        try repo(root, "keep")

        // A linked worktree: `.git` is a file. Its contents are never searched.
        let worktree = try folder(root, "keep-feature")
        try Data("gitdir: /elsewhere\n".utf8).write(to: worktree.appending(path: ".git"))
        try repo(worktree, "inside-worktree")

        for skipped in ["node_modules/pkg", ".build/x", "DerivedData/x", "Pods/x", ".hidden/repo"] {
            try repo(root, skipped)
        }

        // A symlink to a folder holding a repo, outside the root.
        let outside = try repo(temp.url, "outside/linked")
        try fileManager.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)
        try fileManager.createSymbolicLink(
            at: root.appending(path: "link-parent"),
            withDestinationURL: outside.deletingLastPathComponent()
        )

        // A bare repo folder, and a `.git` directory configured as bare.
        let bare = try folder(root, "remote.git")
        try Data("ref: refs/heads/main\n".utf8).write(to: bare.appending(path: "HEAD"))
        try folder(bare, "objects")
        try folder(bare, "refs")
        try repo(bare, "objects/hidden-in-bare")
        let bareConfig = try repo(root, "bare-config")
        try Data("[core]\n\tbare = true\n".utf8).write(to: bareConfig.appending(path: ".git/config"))

        let result = RepoDiscovery().discover(roots: [root])
        #expect(names(result, relativeTo: root) == ["keep"])
        #expect(result.issues.isEmpty)
    }

    @Test func unreadableFolderIsAnIssueNotAFailure() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let root = try folder(temp.url, "root")
        try repo(root, "alpha")
        let locked = try folder(root, "locked")
        try repo(locked, "hidden-repo")
        try repo(root, "zeta")
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = RepoDiscovery().discover(roots: [root])
        #expect(names(result, relativeTo: root) == ["alpha", "zeta"])
        #expect(result.issues.map(\.kind) == [.unreadableFolder])
        #expect(result.issues.first?.path == locked.path)
    }

    @Test func missingRootIsAnIssueAndOverlappingRootsReportOnce() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let root = try folder(temp.url, "root")
        let repoURL = try repo(root, "alpha")
        let missing = temp.url.appending(path: "missing")

        let result = RepoDiscovery().discover(roots: [root, missing, repoURL])
        #expect(result.repos.count == 1)
        #expect(result.issues.map(\.kind) == [.rootMissing])
        #expect(result.issues.first?.path == missing.path)
    }

    @Test func findsRealGitRepos() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        try await fixture.makeRepo("beta", in: fixture.scanRoot.appending(path: "group"))
        try await fixture.addSiblingWorktree(to: alpha, name: "feature")

        let result = RepoDiscovery().discover(roots: [fixture.scanRoot])
        #expect(names(result, relativeTo: fixture.scanRoot) == ["alpha", "group/beta"])
    }
}
