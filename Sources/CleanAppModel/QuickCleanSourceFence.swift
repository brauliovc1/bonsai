import CleanCore
import Foundation

/// Protect source domains even when a checkout has no eligible cleanup operation of its own.
struct QuickCleanSourceFence: Sendable {
    let environment: CleanEnvironment
    let git: Git?
    let roots: [URL]
    let repositories: [String]
    let worktrees: [Worktree]

    func reason(paths: [String], broad: Bool, own: Worktree? = nil, additional: [Worktree] = [], additionalRoots: [URL] = []) -> String? {
        let paths = paths.filter { $0.hasPrefix("/") }.map(CanonicalPath.resolve)
        if broad {
            for root in roots + additionalRoots {
                if paths.contains(where: { CleanupQueue.overlaps($0, CanonicalPath.resolve(root)) }) {
                    return "This cleanup overlaps a source scan folder (\(root.path)); its contents stay."
                }
            }
        }
        var sources = (worktrees + additional).filter { record in
            guard let own else { return true }
            return !CanonicalPath.same(record.url, own.url) || !CanonicalPath.same(record.repoURL, own.repoURL)
        }.map(\.path)
        sources += repositories.filter { repo in own.map { !CanonicalPath.same(URL(fileURLWithPath: repo), $0.url) } ?? true }
        for source in sources {
            let source = CanonicalPath.resolve(source)
            if paths.contains(where: { scope in
                broad ? CleanupQueue.overlaps(scope, source) : (scope == source || source.hasPrefix(scope + "/"))
            }) { return "This cleanup overlaps a protected checkout (\(source)); its source and branches stay." }
        }
        return nil
    }

    /// Called at each broad cleaner's last admission boundary, including after waiting in the queue.
    func freshReason(paths: [String]) async -> String? {
        let currentRoots: [URL]
        do {
            let settings = try SettingsStore(environment: environment).load()
            currentRoots = Scanner.resolveRoots(explicit: [], environment: environment, settings: settings)
        } catch { return "Source folders could not be verified because settings could not be read: \(error)" }
        if let reason = reason(paths: paths, broad: true, additionalRoots: currentRoots) { return reason }
        let repos = Array(Set(repositories + worktrees.map(\.repoPath))).sorted()
        guard !repos.isEmpty else { return nil }
        guard let git else { return "Git is unavailable, so protected checkouts could not be verified." }
        let listings = await BoundedConcurrency.map(repos, limit: 4) { repo -> Listing in
            do {
                let records = try await WorktreeScanner(git: git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
                    .worktrees(in: URL(fileURLWithPath: repo))
                return Listing(records: records, failure: nil)
            } catch { return Listing(records: [], failure: "Protected checkout \(repo) could not be listed again: \(error)") }
        }
        if let failure = listings.compactMap(\.failure).first { return failure }
        return reason(paths: paths, broad: true, additional: listings.flatMap(\.records), additionalRoots: currentRoots)
    }

    private struct Listing: Sendable { let records: [Worktree]; let failure: String? }
}

extension QuickCleanModel {
    var sourceFence: QuickCleanSourceFence {
        QuickCleanSourceFence(environment: app.environment, git: app.git, roots: app.roots,
                             repositories: app.scan?.repos ?? [], worktrees: app.scan?.worktrees ?? [])
    }
}
