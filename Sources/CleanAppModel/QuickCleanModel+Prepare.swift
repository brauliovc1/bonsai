import CleanCore
import Foundation

extension QuickCleanModel {
    func prepare() async -> QuickCleanPlan {
        let settings: Settings
        do { settings = try SettingsStore(environment: app.environment).load() }
        catch { return assemble([], warnings: ["Settings could not be read, so nothing is ready: \(error)"]) }
        await app.refresh()
        guard !Task.isCancelled else { return assemble([], warnings: []) }
        async let cacheReport = caches.scanner.scan()
        async let derivedReport = DerivedDataScanner.scan(environment: app.environment, runner: derivedData.runner)
        async let dockerReport = DockerScanner(environment: app.environment, runner: dockerSimulators.runner).scan()
        async let simulatorReport = SimulatorScanner(environment: app.environment, runner: dockerSimulators.runner).scan()
        async let downloadsReport = downloads.scanner.scan()
        var operations: [QuickCleanOperation] = []
        var warnings = app.issues.map { String(describing: $0) }
        if let problem = app.problem { warnings.append(problem) }
        if let git = app.git, let scan = app.scan {
            var policy = settings; policy.idleThresholdDays = 7
            let assessments = await WorktreeAssessor(git: git, settings: policy, environment: app.environment).assess(scan)
            let eligible = assessments.filter { $0.safety.autoEligible }
            if eligible.contains(where: { $0.worktree.kind == .claude }) { warnings.append(SafetyReason.claudeSessionWarning) }
            operations += eligible.map { worktreeOperation($0, settings: policy, known: scan.worktrees, git: git) }
            let skipped = assessments.count { !$0.worktree.isMain && !$0.safety.autoEligible }
            if skipped > 0 { warnings.append("\(skipped) worktrees are active, protected, unsafe or could not be checked; they stay.") }
            let projectsReport = await ProjectFoldersScanner(git: git, environment: app.environment).scan(
                scan.worktrees, knownWorktrees: scan.worktrees, cwdIndex: await ProcessCwdIndex.capture(in: app.environment),
                includeLeftOut: false)
            warnings += projectsReport.problems
            for project in projectsReport.projects where project.isIdle(atLeast: 7) && project.blocker == nil && project.linkedInUse.isEmpty {
                // A removed worktree owns all its children; never count or clean its folders twice.
                guard !eligible.contains(where: { CleanupQueue.overlaps(CanonicalPath.resolve($0.worktree.url), CanonicalPath.resolve(project.worktree.url)) }) else { continue }
                operations += project.folders.map { projectOperation(project, folder: $0, known: scan.worktrees, git: git) }
            }
        }
        let caches = await cacheReport, derived = await derivedReport
        let docker = await dockerReport, simulators = await simulatorReport, downloads = await downloadsReport
        warnings += caches.warnings + derived.warnings + docker.warnings + simulators.warnings + downloads.warnings
        if let refusal = derived.refusal { warnings.append("DerivedData: \(refusal)") }
        operations += otherOperations(caches: caches, derived: derived, docker: docker, simulators: simulators, downloads: downloads)
        return assemble(operations, warnings: warnings)
    }
}
