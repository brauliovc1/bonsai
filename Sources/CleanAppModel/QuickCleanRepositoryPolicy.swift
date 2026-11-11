import CleanCore
import Foundation

/// The extra Quick clean policy. Existing cleaners still own every deletion and safety check.
struct QuickCleanRepositoryPolicy: Sendable {
    let git: Git
    let environment: CleanEnvironment
    let worktree: Worktree
    let idle: IdleReport
    let known: [Worktree]

    func reason(project: Bool) async -> String? {
        if Task.isCancelled { return "Quick clean was cancelled; nothing was changed." }
        do {
            let records = try await WorktreeScanner(git: git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
                .worktrees(in: worktree.repoURL)
            guard let fresh = records.first(where: { CanonicalPath.same($0.url, worktree.url) }),
                  LightCleanExpectation(worktree: worktree).changes(fresh: fresh).isEmpty else {
                return "The checkout changed since the preview; refresh Quick clean."
            }
            let current: IdleReport
            if project {
                current = await ProjectFoldersScanner(git: git, environment: environment).idleReport(for: fresh, known: known.filter { !CanonicalPath.same($0.repoURL, worktree.repoURL) } + records)
            } else {
                current = await IdleClock(git: git, claudeConfigDirectory: environment.claudeConfigDirectory, now: environment.now).report(for: fresh)
            }
            guard let days = current.idleDays, days >= 7, let newest = current.newest, let confirmed = idle.newest,
                  newest <= confirmed else { return "It was used since the preview or its activity is unknown; nothing was changed." }
            return nil
        } catch { return "The checkout could not be checked again: \(error)" }
    }
}
