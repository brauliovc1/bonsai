import Foundation

/// Fixed-format, read-only queries shared by the map and lineage readers.
struct BranchGit: Sendable {
    let git: GitReadOnly
    static let format = "--format=%H%x00%ct%x00%s%x00%P%x00"

    func commit(_ sha: String) async throws -> BranchHistoryCommit {
        guard let commit = try await commits(sha, maximum: 1).first else { throw CompareError("The commit could not be read.") }
        return commit
    }

    func commits(_ range: String, maximum: Int, flags: [String] = []) async throws -> [BranchHistoryCommit] {
        let data = try await git.data(["log", Self.format, "--max-count=\(maximum)"] + flags + [range, "--"])
        return Self.parse(data)
    }

    func counts(_ base: String, _ tip: String) async throws -> (behind: Int, ahead: Int) {
        let fields = try await git.string(["rev-list", "--left-right", "--count", base + "..." + tip])
            .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard fields.count == 2, fields.allSatisfy({ $0 >= 0 }) else { throw CompareError("Git's branch counts could not be read.") }
        return (fields[0], fields[1])
    }

    func mergeBase(_ base: String, _ tip: String, forkPoint: Bool = false) async throws -> String? {
        let result = try await git.result(["merge-base"] + (forkPoint ? ["--fork-point"] : []) + [base, tip])
        if result.exitCode == 1, !result.timedOut { return nil }
        guard result.succeeded else { throw CompareError(result.timedOut ? "Git took too long." : result.stderr) }
        let sha = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CommitSummary.isHash(sha) else { throw CompareError("The shared commit could not be read.") }
        return sha
    }

    func isAncestor(_ ancestor: String, of descendant: String) async throws -> Bool {
        let result = try await git.result(["merge-base", "--is-ancestor", ancestor, descendant])
        if result.succeeded { return true }
        if result.exitCode == 1, !result.timedOut { return false }
        throw CompareError(result.timedOut ? "Git took too long." : result.stderr)
    }

    static func parse(_ data: Data) -> [BranchHistoryCommit] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var commits: [BranchHistoryCommit] = []
        var index = 0
        while index + 3 < fields.count {
            let sha = String(decoding: fields[index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = TimeInterval(String(decoding: fields[index + 1], as: UTF8.self))
            let subject = String(decoding: fields[index + 2], as: UTF8.self)
            let parents = String(decoding: fields[index + 3], as: UTF8.self).split(separator: " ").map(String.init)
            index += 4
            guard CommitSummary.isHash(sha), let seconds, parents.allSatisfy(CommitSummary.isHash) else { continue }
            commits.append(BranchHistoryCommit(sha: sha, subject: subject, date: Date(timeIntervalSince1970: seconds), parents: parents))
        }
        return commits
    }
}
