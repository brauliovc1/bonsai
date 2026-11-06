import CleanCore
import Foundation

extension WorktreesModel {
    /// What "Clean up missing folders" would clear: `Pruner.preview` of every repo with a missing folder
    /// among the shown rows (filters and search apply), read now.
    public func preparePrune() async -> PrunePlan {
        var repos: [String] = []
        for row in missingFolderRows where !repos.contains(row.worktree.repoPath) {
            repos.append(row.worktree.repoPath)
        }
        guard let git = app.git else {
            return PrunePlan(repos: repos.map { .init(repoPath: $0, entries: [], refusals: [], error: "git not found") })
        }
        let pruner = Pruner(git: git, environment: app.environment)
        var planned: [PrunePlan.Repo] = []
        for repo in repos {
            do {
                let preview = try await pruner.preview(repo: URL(fileURLWithPath: repo, isDirectory: true))
                planned.append(.init(repoPath: repo, entries: preview.entries, refusals: preview.refusals, error: nil))
            } catch {
                planned.append(.init(repoPath: repo, entries: [], refusals: [], error: "\(error)"))
            }
        }
        return PrunePlan(repos: planned)
    }

    /// Opens the prune sheet and fills it with a fresh plan.
    public func beginPrune() async {
        pruneSheetToken += 1
        let token = pruneSheetToken
        prunePlan = nil
        pruneOutcomes = nil
        isShowingPruneSheet = true
        isPreparingPrune = true
        let plan = await preparePrune()
        guard token == pruneSheetToken, isShowingPruneSheet else { return }
        prunePlan = plan
        isPreparingPrune = false
    }

    /// Closes the prune sheet; not while pruning.
    public func dismissPrune() {
        guard !isPruning else { return }
        pruneSheetToken += 1
        isShowingPruneSheet = false
        isPreparingPrune = false
        prunePlan = nil
        pruneOutcomes = nil
    }

    /// `git worktree prune` through `Pruner` for the plan's prunable repos only, each refused unless its
    /// fresh preview has exactly the entries the plan showed. Then rescans.
    @discardableResult
    public func prune(_ plan: PrunePlan) async -> [PruneOutcome] {
        let repos = plan.prunable
        guard !repos.isEmpty, !isPruning, let git = app.git else { return [] }
        isPruning = true
        let pruner = Pruner(git: git, environment: app.environment)
        let finished = await app.cleaningUp {
            var outcomes: [PruneOutcome] = []
            for repo in repos {
                outcomes.append(await Self.prune(repo, with: pruner))
            }
            return outcomes
        }
        let outcomes = finished ?? repos.map {
            PruneOutcome(repoPath: $0.repoPath, pruned: [], refusals: [],
                         error: "another cleanup is still running; nothing was cleared", warnings: [])
        }
        pruneOutcomes = outcomes
        isPruning = false
        if finished != nil { await app.cleanupFinished() }
        return outcomes
    }

    private static func prune(_ repo: PrunePlan.Repo, with pruner: Pruner) async -> PruneOutcome {
        do {
            let result = try await pruner.prune(
                repo: URL(fileURLWithPath: repo.repoPath, isDirectory: true),
                expectedEntries: Set(repo.entries)
            )
            return PruneOutcome(repoPath: repo.repoPath, pruned: result.pruned, refusals: [], error: nil,
                                warnings: result.warnings)
        } catch let refused as Pruner.Refused {
            return PruneOutcome(repoPath: repo.repoPath, pruned: [], refusals: refused.refusals, error: nil, warnings: [])
        } catch {
            return PruneOutcome(repoPath: repo.repoPath, pruned: [], refusals: [], error: "\(error)", warnings: [])
        }
    }
}
