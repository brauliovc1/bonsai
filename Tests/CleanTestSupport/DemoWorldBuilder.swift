import CleanCore
import Foundation

/// Builds `DemoWorld`'s repos and worktrees.
///
/// Every git command that shapes an aged worktree (commit, `worktree add`, clone) runs with
/// GIT_AUTHOR_DATE and GIT_COMMITTER_DATE set to that worktree's date, because reflog entries take the
/// committer date and the idle clock reads the last `logs/HEAD` entry. When everything is built, the
/// worktree's files and its git dir's `index` and `HEAD` get that date as their mtime.
struct DemoWorldBuilder {
    let fixture: GitFixture
    let now: Date

    static let gitignore = ".env\nnode_modules/\n.venv/\n.build/\n/.claude/worktrees/\n*.log\n"

    /// An hour past the whole day, so the idle clock reads `days` for the next 23 hours.
    func date(daysAgo days: Int) -> Date {
        now.addingTimeInterval(-(TimeInterval(days) * 86_400 + 3_600))
    }

    func build() async throws -> (repos: [URL], items: [DemoWorld.Item]) {
        let atlas = try await makeRepo("atlas")
        let beacon = try await makeRepo("beacon")
        let cobalt = try await makeRepo("cobalt")
        var items: [DemoWorld.Item] = []

        // atlas: the plain cases.
        let archive = try await pushedSibling(of: atlas, "archive", days: 45)
        items.append(.init(
            url: archive, repo: atlas, purpose: "clean, pushed, 45 days idle", idleDays: 45, status: "AUTO-READY"
        ))
        let review = try await pushedSibling(of: atlas, "review", days: 10)
        items.append(.init(
            url: review, repo: atlas, purpose: "clean, pushed, 10 days idle", idleDays: 10, status: "SAFE",
            notes: ["active 10d ago"]
        ))
        let wip = try await sibling(of: atlas, "wip", days: 3)
        try fixture.write("# atlas\n\nHalf-written change.\n", to: "README.md", in: wip)
        try fixture.write("todo\n", to: "scratch.md", in: wip)
        items.append(.init(
            url: wip, repo: atlas, purpose: "uncommitted changes (2 files)", idleDays: 3,
            status: "BLOCKED: uncommitted"
        ))
        let claude = atlas.appending(path: ".claude/worktrees/tidy-otter", directoryHint: .isDirectory)
        try await worktreeAdd(atlas, claude, branch: "claude/tidy-otter", days: 45)
        try await commitAndPush(claude, file: "notes/otter.md", branch: "claude/tidy-otter", days: 45)
        items.append(.init(
            url: claude, repo: atlas, purpose: "Claude worktree, clean, 45 days idle", idleDays: 45,
            status: "SAFE", notes: ["Claude session"]
        ))

        // beacon: work that exists only here, and a deleted folder.
        let spike = try await sibling(of: beacon, "spike", days: 20)
        try await commit(spike, file: "spike.md", days: 20)
        items.append(.init(
            url: spike, repo: beacon, purpose: "1 local-only commit on its branch", idleDays: 20,
            status: "SAFE", notes: ["local-only commits (1)", "active 20d ago"]
        ))
        let bisect = beacon.deletingLastPathComponent().appending(path: "beacon-bisect", directoryHint: .isDirectory)
        try await git(["worktree", "add", "--quiet", "--detach", bisect.path], in: beacon, days: 15)
        try await commit(bisect, file: "probe.md", days: 15)
        items.append(.init(
            url: bisect, repo: beacon, purpose: "detached HEAD with 1 local-only commit", idleDays: 15,
            status: "BLOCKED: local-only commits"
        ))
        let env = try await pushedSibling(of: beacon, "env", days: 40)
        try fixture.write("API_TOKEN=demo-only\n", to: ".env", in: env)
        items.append(.init(
            url: env, repo: beacon, purpose: "clean, pushed, an ignored .env, 40 days idle", idleDays: 40,
            status: "SAFE", notes: ["ignored files (1)"]
        ))
        let gone = try await pushedSibling(of: beacon, "gone", days: 50)
        try fixture.deleteFolder(gone)
        items.append(.init(
            url: gone, repo: beacon, purpose: "folder deleted (prunable)", idleDays: nil,
            status: "BLOCKED: folder missing"
        ))

        // cobalt: dependency folders and nested clones.
        let web = try await pushedSibling(of: cobalt, "web", days: 5)
        try writeNodeModules(in: web)
        items.append(.init(
            url: web, repo: cobalt, purpose: "20 MB ignored node_modules, 5 days idle", idleDays: 5,
            status: "SAFE", notes: ["active 5d ago"]
        ))
        let swift = try await pushedSibling(of: cobalt, "swift", days: 12)
        let kit = swift.appending(path: ".build/checkouts/demo-kit", directoryHint: .isDirectory)
        try await nestedClone("demo-kit", at: kit, days: 12, unpushedCommit: false)
        items.append(.init(
            url: swift, repo: cobalt, purpose: "package copy in .build/checkouts, 12 days idle",
            idleDays: 12, status: "SAFE", notes: ["package copies (1)"]
        ))
        let python = try await pushedSibling(of: cobalt, "py", days: 25)
        let package = python.appending(path: ".venv/src/mypkg", directoryHint: .isDirectory)
        try await nestedClone("mypkg", at: package, days: 25, unpushedCommit: true)
        items.append(.init(
            url: python, repo: cobalt, purpose: ".venv/src/mypkg clone with an unpushed commit", idleDays: 25,
            status: "BLOCKED: nested checkouts"
        ))

        // Last, so no later git command moves an mtime again.
        for item in items {
            guard let days = item.idleDays else { continue }
            try await age(item.url, to: date(daysAgo: days))
        }
        return ([atlas, beacon, cobalt], items)
    }

    // MARK: - Steps

    /// A bare remote plus a main clone in the scan root, with README and .gitignore pushed to `main`.
    private func makeRepo(_ name: String) async throws -> URL {
        let days = 60
        let clone = fixture.scanRoot.appending(path: name, directoryHint: .isDirectory)
        let remote = fixture.remotes.appending(path: "\(name).git", directoryHint: .isDirectory)
        try await git(["init", "--quiet", "--bare", remote.path], in: fixture.url, days: days)
        try await git(["clone", "--quiet", remote.path, clone.path], in: fixture.url, days: days)
        try fixture.write("# \(name)\n", to: "README.md", in: clone)
        try fixture.write(Self.gitignore, to: ".gitignore", in: clone)
        try await git(["add", "-A"], in: clone, days: days)
        try await git(["commit", "--quiet", "-m", "Initial commit"], in: clone, days: days)
        try await git(["push", "--quiet", "-u", "origin", "main"], in: clone, days: days)
        return clone
    }

    /// `<parent>/<repo>-<name>` on a new branch `<name>`.
    private func sibling(of repo: URL, _ name: String, days: Int) async throws -> URL {
        let path = repo.deletingLastPathComponent()
            .appending(path: "\(repo.lastPathComponent)-\(name)", directoryHint: .isDirectory)
        try await worktreeAdd(repo, path, branch: name, days: days)
        return path
    }

    /// A sibling with one commit of its own, pushed to `origin/<name>`.
    private func pushedSibling(of repo: URL, _ name: String, days: Int) async throws -> URL {
        let path = try await sibling(of: repo, name, days: days)
        try await commitAndPush(path, file: "notes/\(name).md", branch: name, days: days)
        return path
    }

    private func worktreeAdd(_ repo: URL, _ path: URL, branch: String, days: Int) async throws {
        try await git(["worktree", "add", "--quiet", "-b", branch, path.path], in: repo, days: days)
    }

    private func commit(_ folder: URL, file: String, days: Int) async throws {
        try fixture.write("\(file)\n", to: file, in: folder)
        try await git(["add", "-A"], in: folder, days: days)
        try await git(["commit", "--quiet", "-m", "Add \(file)"], in: folder, days: days)
    }

    private func commitAndPush(_ folder: URL, file: String, branch: String, days: Int) async throws {
        try await commit(folder, file: file, days: days)
        try await git(["push", "--quiet", "-u", "origin", branch], in: folder, days: days)
    }

    /// A clone of a new bare remote at `path`, with one pushed commit and optionally one that isn't.
    private func nestedClone(_ name: String, at path: URL, days: Int, unpushedCommit: Bool) async throws {
        let remote = fixture.remotes.appending(path: "\(name).git", directoryHint: .isDirectory)
        try await git(["init", "--quiet", "--bare", remote.path], in: fixture.url, days: days)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await git(["clone", "--quiet", remote.path, path.path], in: fixture.url, days: days)
        try await commitAndPush(path, file: "Sources/\(name).txt", branch: "main", days: days)
        if unpushedCommit { try await commit(path, file: "local-fix.txt", days: days) }
    }

    /// 20 MB in `node_modules`, which §4.2 treats as regenerable.
    private func writeNodeModules(in folder: URL) throws {
        try fixture.write("module.exports = (s, n) => s.padStart(n)\n", to: "node_modules/left-pad/index.js", in: folder)
        let cache = folder.appending(path: "node_modules/.cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let chunk = Data(repeating: 0x2A, count: 5 * 1024 * 1024)
        for index in 1...4 {
            try chunk.write(to: cache.appending(path: "blob-\(index).bin"))
        }
    }

    /// Sets the mtime of every file in the worktree and of `index` and `HEAD` in its git dir.
    private func age(_ worktree: URL, to date: Date) async throws {
        let gitDir = URL(fileURLWithPath: try await fixture.run(["rev-parse", "--absolute-git-dir"], in: worktree))
        try fixture.setModificationDate(date, of: worktree, recursively: true)
        for name in ["index", "HEAD"] {
            try fixture.setModificationDate(date, of: gitDir.appending(path: name))
        }
    }

    /// The fixture's isolated git, with author and committer dates set to `days` ago.
    private func git(_ arguments: [String], in directory: URL, days: Int) async throws {
        let stamp = "\(Int(date(daysAgo: days).timeIntervalSince1970)) +0000"
        try await fixture.run(arguments, in: directory, adding: ["GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp])
    }
}
