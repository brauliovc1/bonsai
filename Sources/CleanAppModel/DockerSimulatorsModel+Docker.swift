import CleanCore
import Foundation

extension DockerSimulatorsModel {
    /// The Docker sheet's content, from a scan made now: the daemon's state, so the command and whether it
    /// may run are the ones in force.
    public func prepareDockerPrune() async -> DockerPruneConfirmation {
        let fresh = await DockerScanner(environment: app.environment, runner: runner).scan()
        docker = fresh
        let commandLine = DockerCleaner(environment: app.environment, runner: runner)?.commandLine
        return DockerPruneConfirmation(report: fresh, commandLine: commandLine)
    }

    /// Opens the Docker sheet and fills it once the scan is done.
    public func beginDockerPrune() async {
        dockerSheetToken += 1
        let token = dockerSheetToken
        dockerReport = nil
        dockerConfirmation = nil
        isShowingDockerSheet = true
        isPreparingDocker = true
        let prepared = await prepareDockerPrune()
        // Closed (or opened again) while looking: drop this result.
        guard token == dockerSheetToken, isShowingDockerSheet else { return }
        dockerConfirmation = prepared
        isPreparingDocker = false
    }

    /// Closes the sheet; not while the prune runs.
    public func dismissDockerPrune() {
        guard !isPruning else { return }
        dockerSheetToken += 1
        isShowingDockerSheet = false
        isPreparingDocker = false
        dockerConfirmation = nil
        dockerReport = nil
    }

    /// Runs `docker system prune -f` through `DockerCleaner.run(ifConfirmed:report:)`, with a scan made
    /// right before (the daemon may have stopped, or been replaced, since the sheet opened). CleanCore
    /// writes the log entry; if that fails the report says so. Then the screen scans again.
    @discardableResult
    public func confirmDockerPrune(_ confirmation: DockerPruneConfirmation) async -> CleanupCommandReport {
        guard confirmation.isAllowed, !isPruning else {
            return show(prune: Self.dockerReport(error: confirmation.blocker ?? "A prune is already running.", result: nil))
        }
        isPruning = true
        let finished = await app.cleaningUp { await runPrune() }
        let report = finished ?? Self.dockerReport(error: "Another cleanup is still running.", result: nil)
        isPruning = false
        _ = show(prune: report)
        if finished != nil {
            await app.cleanupFinished(rescanWorktrees: false)
            await refresh()
        }
        return report
    }

    private func runPrune() async -> CleanupCommandReport {
        let current = await DockerScanner(environment: app.environment, runner: runner).scan()
        docker = current
        guard let cleaner = DockerCleaner(environment: app.environment, runner: runner) else {
            return Self.dockerReport(error: "Docker is not installed.", result: nil)
        }
        do {
            guard let result = try await cleaner.run(ifConfirmed: true, report: current) else {
                return Self.dockerReport(error: "The prune was not confirmed.", result: nil)
            }
            return Self.dockerReport(error: nil, result: result)
        } catch let refused as DockerCleaner.Refused {
            return Self.dockerReport(error: refused.description, result: nil)
        } catch {
            return Self.dockerReport(error: "docker could not be started: \(error)", result: nil)
        }
    }

    private func show(prune report: CleanupCommandReport) -> CleanupCommandReport {
        dockerReport = report
        return report
    }

    private static func dockerReport(error: String?, result: CleanupCommandResult?) -> CleanupCommandReport {
        CleanupCommandReport(kind: .dockerPrune, command: DockerPruneConfirmation.command, result: result, error: error)
    }
}
