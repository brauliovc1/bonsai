import Foundation

/// Reads the git and disk state the §4.1 checks need for one linked worktree. Read-only.
public struct WorktreeInspector: Sendable {
    public var git: Git
    /// How many entries of each ignored folder are looked at on disk.
    public var searchLimit: Int

    public init(git: Git, searchLimit: Int = 10_000) {
        self.git = git
        self.searchLimit = searchLimit
    }

    /// `knownWorktrees`: other worktrees from the same scan (or a fresh listing); any inside this one
    /// counts as a nested checkout.
    public func inspect(_ worktree: Worktree, knownWorktrees: [Worktree] = []) async -> WorktreeState {
        let folder = worktree.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return .missing }

        var state = WorktreeState()
        // Without its own `.git` file, git commands in the folder would describe an enclosing repo.
        do {
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: folder)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), folder) else {
                state.gitErrors.append("git sees \(topLevel) here, not this worktree; its .git file is missing or broken")
                return state
            }
        } catch {
            state.gitErrors.append("\(error)")
            return state
        }

        state.hasSubmodules = FileManager.default.fileExists(atPath: folder.appending(path: ".gitmodules").path)

        do {
            let status = try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: folder)
            state.changedFiles = Self.countStatusEntries(status)
        } catch {
            state.gitErrors.append("\(error)")
        }

        do {
            let count = try await git.gitString(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: folder)
            guard let value = Int(count) else { throw GitError(exitCode: 0, stderr: count, arguments: ["rev-list"]) }
            state.localOnlyCommits = value
        } catch {
            state.gitErrors.append("\(error)")
        }

        if let branch = worktree.branch {
            do {
                let stashes = try await git.gitString(["stash", "list", "--format=%gs"], in: folder)
                state.branchStashes = Self.countStashes(stashes, branch: branch)
            } catch {
                state.gitErrors.append("\(error)")
            }
        }

        do {
            let output = try await git.git(
                ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"],
                in: folder
            )
            let ignored = output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            let search = IgnoredFolderSearch(limit: searchLimit)
            let userFiles = ignored.filter { entry in
                if RegenerableNames.isHarmlessIgnoredPath(entry) { return false }
                guard entry.hasSuffix("/") else { return true }
                return search.holdsUserFiles(folder.appending(path: entry, directoryHint: .isDirectory))
            }
            state.ignoredUserFiles = IgnoredFolderSearch.topmost(userFiles)
        } catch {
            state.gitErrors.append("\(error)")
        }

        state.nestedCheckouts = nestedCheckouts(in: worktree, knownWorktrees: knownWorktrees, ignored: state.ignoredUserFiles)
        return state
    }

    /// Registered worktrees inside this folder, plus `.git` entries found in its ignored user folders
    /// (untracked ones already show up in `git status`).
    private func nestedCheckouts(in worktree: Worktree, knownWorktrees: [Worktree], ignored: [String]) -> [String] {
        var found = knownWorktrees
            .filter { CanonicalPath.isInside($0.url, directory: worktree.url) }
            .compactMap { CanonicalPath.relativePath(of: $0.url, to: worktree.url) }
        let search = IgnoredFolderSearch(limit: searchLimit)
        for entry in ignored where entry.hasSuffix("/") {
            found += search.checkouts(in: worktree.url.appending(path: entry, directoryHint: .isDirectory))
                .compactMap { CanonicalPath.relativePath(of: $0, to: worktree.url) }
        }
        return found.uniqued().sorted()
    }

    /// Entries of `status --porcelain=v1 -z`. A rename or copy (`R`/`C`) is followed by its source path,
    /// which is not a separate entry.
    static func countStatusEntries(_ data: Data) -> Int {
        let fields = data.split(separator: 0)
        var count = 0
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            count += 1
            let codes = field.prefix(2)
            index += codes.contains(UInt8(ascii: "R")) || codes.contains(UInt8(ascii: "C")) ? 2 : 1
        }
        return count
    }

    /// Stash subjects made on `branch`: `WIP on <branch>: ...` or `On <branch>: ...`.
    static func countStashes(_ output: String, branch: String) -> Int {
        output.split(separator: "\n").filter { line in
            line.hasPrefix("WIP on \(branch):") || line.hasPrefix("On \(branch):")
        }.count
    }
}
