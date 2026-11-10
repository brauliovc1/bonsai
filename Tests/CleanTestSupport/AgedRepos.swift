import CleanCore
import Foundation

/// Real git repos whose idle clock (PLAN §4.3) reads a chosen number of days: every git command runs with
/// author and committer dates that many days back (reflog entries take the committer date), and `age` sets
/// the files' and the git dir's `index` and `HEAD` mtimes last.
public struct AgedRepos: Sendable {
    public let fixture: GitFixture
    /// The moment the ages count back from.
    public let now: Date

    public init(fixture: GitFixture, now: Date = Date()) {
        self.fixture = fixture
        self.now = now
    }

    /// An hour past the whole day, so the idle clock reads `days` for the next 23 hours.
    public func date(daysAgo days: Int) -> Date {
        now.addingTimeInterval(-(TimeInterval(days) * 86_400 + 3_600))
    }

    /// A bare remote and a main clone at `<parent>/<name>` (default: the scan root) with `files` and
    /// `gitignore` pushed to `main`.
    public func repo(_ name: String, days: Int, gitignore: String, files: [String: String] = [:], in parent: URL? = nil) async throws -> URL {
        let clone = (parent ?? fixture.scanRoot).appending(path: name, directoryHint: .isDirectory)
        let remote = fixture.remotes.appending(path: "\(name).git", directoryHint: .isDirectory)
        try await git(["init", "--quiet", "--bare", remote.path], in: fixture.url, days: days)
        try await git(["clone", "--quiet", remote.path, clone.path], in: fixture.url, days: days)
        try fixture.write(gitignore, to: ".gitignore", in: clone)
        for (path, text) in files { try fixture.write(text, to: path, in: clone) }
        try await git(["add", "-A"], in: clone, days: days)
        try await git(["commit", "--quiet", "-m", "Initial commit"], in: clone, days: days)
        try await git(["push", "--quiet", "-u", "origin", "main"], in: clone, days: days)
        return clone
    }

    public func commitAndPush(_ folder: URL, file: String, branch: String, days: Int) async throws {
        try fixture.write("\(file)\n", to: file, in: folder)
        try await git(["add", "-A"], in: folder, days: days)
        try await git(["commit", "--quiet", "-m", "Add \(file)"], in: folder, days: days)
        try await git(["push", "--quiet", "-u", "origin", branch], in: folder, days: days)
    }

    /// A file of `megabytes` MB (or `kibibytes` KiB) at `relative` inside `folder`, parents created.
    public func blob(in folder: URL, _ relative: String, megabytes: Int = 0, kibibytes: Int = 0) throws {
        let file = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: megabytes * 1024 * 1024 + kibibytes * 1024).write(to: file)
    }

    /// Every file's mtime (a symlink's own too), and `index` and `HEAD` in the checkout's git dir.
    public func age(_ checkout: URL, days: Int) async throws {
        let gitDir = URL(fileURLWithPath: try await fixture.run(["rev-parse", "--absolute-git-dir"], in: checkout))
        try fixture.setModificationDate(date(daysAgo: days), of: checkout, recursively: true)
        ageSymlinks(in: checkout, to: date(daysAgo: days))
        for name in ["index", "HEAD"] {
            try fixture.setModificationDate(date(daysAgo: days), of: gitDir.appending(path: name))
        }
    }

    /// `setModificationDate` follows a symlink to its target; the idle clock reads the link's own mtime.
    private func ageSymlinks(in folder: URL, to date: Date) {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path) else { return }
        while let relative = enumerator.nextObject() as? String {
            let path = folder.appending(path: relative).path
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else { continue }
            let stamp = timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)
            var times = [stamp, stamp]
            lutimes(path, &times)
        }
    }

    /// The fixture's git with author and committer dates `days` ago (reflog entries take the committer date).
    public func git(_ arguments: [String], in directory: URL, days: Int) async throws {
        let stamp = "\(Int(date(daysAgo: days).timeIntervalSince1970)) +0000"
        try await fixture.run(arguments, in: directory, adding: ["GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp])
    }
}
