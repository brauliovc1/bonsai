import Foundation

/// The §4.1 rows added on 11-06 that read git's own files: hidden local edits, operations in progress and
/// detached reflog-only commits.
extension WorktreeInspector {
    /// Files in the git dir that mean an operation is half done.
    public static let operationMarkers = [
        "rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
    ]

    static func operationsInProgress(gitDir: URL) -> [String] {
        operationMarkers.filter { Remover.itemExists(at: gitDir.appending(path: $0).path) }
    }

    /// Tracked files marked `assume-unchanged` (lowercase tag in `ls-files -v`) or `skip-worktree` (`S`)
    /// that exist on disk: `git status` never shows edits to them. Absent files (sparse checkout) don't count.
    func hiddenEdits(in folder: URL) async throws -> [String] {
        let output = try await git.git(["ls-files", "-v", "-z"], in: folder)
        return Self.hiddenEditCandidates(output).filter { path in
            Remover.itemExists(at: folder.appending(path: path).path)
        }
    }

    /// Paths of `ls-files -v -z` entries (`<tag> <path>`) whose tag is lowercase or `S`.
    static func hiddenEditCandidates(_ data: Data) -> [String] {
        data.split(separator: 0).compactMap { field in
            guard field.count > 2, let tag = field.first, field[field.startIndex + 1] == UInt8(ascii: " ") else {
                return nil
            }
            let flagged = (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(tag) || tag == UInt8(ascii: "S")
            return flagged ? String(decoding: field.dropFirst(2), as: UTF8.self) : nil
        }
    }

    /// The commits named in this worktree's own `logs/HEAD` (deleted with the worktree) that no branch, tag or
    /// remote ref reaches, each once (full shas). Commits git already collected don't count: nothing is left to
    /// lose.
    func reflogOnlyCommits(gitDir: URL, in folder: URL) async throws -> [String] {
        let reflog = gitDir.appending(path: "logs/HEAD")
        let data: Data
        do {
            data = try Data(contentsOf: reflog)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let commits = Self.reflogCommits(data)
        var found: [String] = []
        var seen: Set<String> = []
        var start = commits.startIndex
        while start < commits.endIndex {
            let chunk = commits[start..<min(start + 2_000, commits.endIndex)]
            let listed = try await git.gitString(
                ["rev-list", "--ignore-missing"] + chunk + ["--not", "--branches", "--tags", "--remotes"],
                in: folder
            )
            for sha in listed.split(separator: "\n").map(String.init) where seen.insert(sha).inserted {
                found.append(sha)
            }
            start += 2_000
        }
        return found
    }

    /// The old and new object names of every reflog line, without the all-zero name, each once.
    static func reflogCommits(_ data: Data) -> [String] {
        var seen: Set<String> = []
        var commits: [String] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            for word in line.split(separator: UInt8(ascii: " "), maxSplits: 2).prefix(2) {
                let name = String(decoding: word, as: UTF8.self)
                guard name.count >= 40, name.allSatisfy(\.isHexDigit), name.contains(where: { $0 != "0" }) else { continue }
                if seen.insert(name).inserted { commits.append(name) }
            }
        }
        return commits
    }
}
