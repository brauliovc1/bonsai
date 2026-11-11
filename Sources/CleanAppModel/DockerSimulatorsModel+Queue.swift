import Foundation

extension DockerSimulatorsModel {
    public static let dockerResource = "command:docker"
    public static let simulatorsResource = "command:simulators"

    @discardableResult
    public func queueDockerPrune(_ confirmation: DockerPruneConfirmation) -> CleanupTask? {
        guard confirmation.isAllowed else { return nil }
        let item = CleanupItem(name: "Docker", resources: [Self.dockerResource], estimatedBytes: confirmation.estimatedBytes,
                               sizeEstimates: [confirmation.hasSizeEstimate ? confirmation.estimatedBytes : nil])
        let task = app.cleanupQueue.enqueue(title: "Docker", unit: "commands", work: [CleanupWork(item) {
            CleanupItemResult(await self.runPrune())
        }]) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { dismissDockerPrune() }
        return task
    }

    @discardableResult
    public func queueSimulatorsDelete(_ confirmation: SimulatorsConfirmation) -> CleanupTask? {
        guard confirmation.isAllowed else { return nil }
        let item = CleanupItem(name: "Unavailable simulators", resources: [Self.simulatorsResource], estimatedBytes: confirmation.estimatedBytes,
                               sizeEstimates: confirmation.devices.map(\.sizeBytes))
        let task = app.cleanupQueue.enqueue(title: "Simulators", unit: "commands", work: [CleanupWork(item) {
            CleanupItemResult(await self.runDelete(confirmed: confirmation.devices, estimatedBytes: confirmation.estimatedBytes))
        }]) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { dismissSimulatorsDelete() }
        return task
    }
}
