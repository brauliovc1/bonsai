import Foundation

extension BranchLineageReader {
    func merged(tip: String, base: String) async -> BranchMergeState {
        do {
            let query = BranchGit(git: git)
            if try await query.isAncestor(tip, of: base) {
                let merges = try await query.commits(tip + ".." + base, maximum: 100_000,
                    flags: ["--first-parent", "--merges", "--reverse", "--topo-order", "--ancestry-path"])
                if merges.count == 100_000 { return BranchMergeState(.unavailable, detail: "This history has too many merge commits to inspect completely.") }
                for commit in merges {
                    try Task.checkCancellation()
                    guard let first = commit.parents.first else { continue }
                    if try await query.isAncestor(tip, of: first) { break }
                    for parent in commit.parents.dropFirst() where try await query.isAncestor(tip, of: parent) {
                        return BranchMergeState(.mergeCommit, commit: commit)
                    }
                }
            }
            let check = await MergeCheck.check(base: base, compare: tip, using: git)
            if check.state == .unavailable { return BranchMergeState(.unavailable, detail: check.detail) }
            if check.state == .clean, let tree = check.treeSHA {
                let baseTree = try await git.string(["rev-parse", "--verify", "--end-of-options", base + "^{tree}"])
                if tree == baseTree { return BranchMergeState(.changesInBase) }
            }
            return BranchMergeState(.notMerged)
        } catch { return BranchMergeState(.unavailable, detail: String(describing: error)) }
    }

    func upstream(_ ref: String) async -> BranchUpstream {
        do {
            if BranchTrackingConfig.hasIncludes(common: git.commonDirectory, worktree: git.gitDirectory) {
                return BranchUpstream(ref: nil, problem: "Tracking settings in included config are not read.")
            }
            let data = try await git.data(["for-each-ref", "--format=%(refname)%00%(upstream)", ref])
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first { line in
                line.split(separator: "\0", omittingEmptySubsequences: false).first.map(String.init) == ref
            }
            let fields = line?.split(separator: "\0", omittingEmptySubsequences: false) ?? []
            guard fields.count == 2, !fields[1].isEmpty else { return BranchUpstream(ref: nil) }
            let tracking = String(fields[1])
            let tip = try await git.resolve(ref), upstream = try await git.resolve(tracking)
            let counts = try await BranchGit(git: git).counts(upstream, tip)
            return BranchUpstream(ref: tracking, ahead: counts.ahead, behind: counts.behind)
        } catch { return BranchUpstream(ref: nil, problem: "Couldn't read the upstream: \(error)") }
    }
}
