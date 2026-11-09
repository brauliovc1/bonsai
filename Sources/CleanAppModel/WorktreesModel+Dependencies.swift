import CleanCore
import Foundation

extension WorktreesModel {
    /// Folders measured at the same time.
    static let dependencyConcurrency = 2

    /// The first measurement of every checkout's dependency folders: runs once, the first time the screen has
    /// rows to measure.
    public func computeDependenciesIfNeeded() async {
        guard !hasRequestedDependencies, !isMeasuringDependencies, !app.assessments.isEmpty else { return }
        await computeDependencies()
    }

    /// Measures the light-clean folders of every worktree of the last scan (not only the shown rows), a few
    /// at a time, each row showing a spinner until its number is in. The toolbar button runs this again.
    public func computeDependencies() async {
        guard !isMeasuringDependencies else { return }
        isMeasuringDependencies = true
        hasRequestedDependencies = true
        await measureDependencies(of: allRows)
        isMeasuringDependencies = false
    }

    /// Measures again after a light clean touched these rows.
    func measureDependencies(of ids: Set<WorktreeRow.ID>) async {
        await measureDependencies(of: allRows.filter { ids.contains($0.id) })
    }

    /// A cleanup changed these checkouts' dependency folders (here or on Project folders): the ones measured
    /// before are measured again, so "Clean dependencies…" and the details panel show what is left.
    func checkoutsChanged(_ paths: Set<String>) async {
        let measured = allRows.filter { row in
            paths.contains(row.path) && (hasRequestedDependencies || dependencySizes[row.id] != nil)
        }
        await measureDependencies(of: Set(measured.map(\.id)))
    }

    private func measureDependencies(of targets: [WorktreeRow]) async {
        guard !targets.isEmpty else { return }
        guard let git = app.git else {
            for row in targets { dependencySizes[row.id] = .measured(nil) }
            return
        }
        // A bare entry, a missing folder or another repo's folder has nothing this row could clean.
        let work = targets.filter(Self.isMeasurable)
        for row in targets where !Self.isMeasurable(row) { dependencySizes[row.id] = .measured(nil) }
        for row in work { dependencySizes[row.id] = .measuring }

        let finder = LightCleanFinder(git: git, du: app.environment.tools.du)
        let known = app.scan?.worktrees ?? []
        await withTaskGroup(of: (WorktreeRow.ID, Int64?).self) { group in
            var next = 0
            func startNext() {
                guard next < work.count else { return }
                let row = work[next]
                next += 1
                group.addTask {
                    let findings = await finder.candidates(in: row.worktree, knownWorktrees: known)
                    let estimates = findings.candidates.compactMap(\.estimatedBytes)
                    return (row.id, estimates.isEmpty ? nil : estimates.reduce(0, +))
                }
            }
            for _ in 0..<Self.dependencyConcurrency { startNext() }
            for await (id, bytes) in group {
                dependencySizes[id] = .measured(bytes)
                startNext()
            }
        }
    }

    private static func isMeasurable(_ row: WorktreeRow) -> Bool {
        let worktree = row.worktree
        return !worktree.isBare && !worktree.isPrunable && !row.isMissingFolder && !row.isStaleRecord
    }
}
