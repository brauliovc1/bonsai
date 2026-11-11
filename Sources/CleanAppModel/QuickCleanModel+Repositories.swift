import CleanCore
import Foundation

extension QuickCleanModel {
    func worktreeOperation(_ assessment: WorktreeAssessment, settings: Settings, known: [Worktree], git: Git) -> QuickCleanOperation {
        let worktree = assessment.worktree, environment = app.environment
        let configure = configureRemover
        let policy = QuickCleanRepositoryPolicy(git: git, environment: environment, worktree: worktree, idle: assessment.idle, known: known)
        let preview = QuickCleanItem(id: "worktree:" + worktree.path, title: DisplayText.branch(of: worktree),
            detail: "Remove this worktree; keep its branch. Idle \(assessment.idle.idleDays ?? 0) days.", path: worktree.path,
            estimatedBytes: assessment.estimatedBytes)
        let work = CleanupWork(CleanupItem(name: preview.title, resources: [worktree.path], estimatedBytes: preview.estimatedBytes)) {
            var remover = Remover(git: git, settings: settings, environment: environment)
            configure(&remover)
            do {
                let result = try await remover.remove(worktree, mode: .auto, estimatedBytes: assessment.estimatedBytes,
                    knownWorktrees: known, expectation: RemovalExpectation(assessment: assessment), logMode: .manual, stillAllowed: {
                        guard await policy.reason(project: false) == nil else { return .rulesChanged }
                        guard let latest = try? SettingsStore(environment: environment).load(),
                              worktree.kind != .claude || latest.includeClaudeInAuto else { return .rulesChanged }
                        return nil
                    })
                return CleanupItemResult(.cleaned, freedBytes: result.freedBytes, detail: "Worktree removed; branch kept.", warnings: result.warnings)
            } catch {
                return CleanupItemResult(.refused, detail: "Left alone because it changed, became active or could not pass its safety checks: \(error)")
            }
        }
        return QuickCleanOperation(kind: .worktrees, items: [preview], work: work, removed: worktree)
    }

    func projectOperation(_ project: ProjectFolders, folder: ProjectFolders.Folder, known: [Worktree], git: Git) -> QuickCleanOperation {
        let worktree = project.worktree, environment = app.environment
        let configure = configureLightCleaner
        let candidate = folder.candidate
        let policy = QuickCleanRepositoryPolicy(git: git, environment: environment, worktree: worktree, idle: project.idle, known: known)
        let preview = QuickCleanItem(id: "project:" + candidate.url.path, title: candidate.relativePath,
            detail: ([DisplayText.repoName(worktree.repoPath), "Idle \(project.idleDays ?? 0) days"] + project.rebuildLines).joined(separator: " · "),
            path: candidate.url.path, estimatedBytes: folder.bytes)
        let work = CleanupWork(CleanupItem(name: preview.title, resources: [candidate.url.path], estimatedBytes: folder.bytes)) {
            var cleaner = LightCleaner(git: git, environment: environment)
            configure(&cleaner)
            cleaner.admission = { fresh, _ in
                if let reason = await policy.reason(project: true) { return reason }
                let index = await ProcessCwdIndex.capture(in: environment)
                if let reason = LightCleaner.inUseReason(index, worktree: fresh.url) { return reason.sentence }
                let records: [Worktree]
                do {
                    records = try await WorktreeScanner(git: git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
                        .worktrees(in: fresh.repoURL)
                } catch { return "Its linked worktrees could not be checked again: \(error)" }
                let currentKnown = records + known.filter { !CanonicalPath.same($0.repoURL, fresh.repoURL) }
                if let reason = LightCleanFlow.linkedUse(of: fresh, known: currentKnown, index: index) { return reason }
                return await policy.reason(project: true)
            }
            do {
                let result = try await cleaner.clean(worktree, candidates: [candidate], knownWorktrees: known,
                                                     expectation: LightCleanExpectation(worktree: worktree))
                return CleanupItemResult(LightCleanOutcome(item: LightCleanConfirmation.Item(
                    worktree: worktree, findings: LightCleanFindings(worktree: worktree, candidates: [candidate]), blocker: nil), result: result))
            } catch { return CleanupItemResult(.refused, detail: "Left alone: \(error)") }
        }
        return QuickCleanOperation(kind: .projects, items: [preview], work: work, touched: worktree)
    }
}
