import CleanCore
import Foundation

extension QuickCleanModel {
    func otherOperations(caches: ToolCacheReport, derived: DerivedDataReport, docker: DockerReport,
                         simulators: SimulatorReport, downloads: DownloadsReport) -> [QuickCleanOperation] {
        var result: [QuickCleanOperation] = []
        let environment = app.environment
        let fence = sourceFence
        let originalProcesses = self.caches.processes
        for finding in caches.ready {
            let paths: [String]
            if finding.entry.deletion == .contents {
                paths = finding.entry.targets.map { environment.homeDirectory.appending(path: $0).path }
            } else { paths = finding.removals }
            let scope = finding.entry.deletion == .contents ? "Contents of these cache folders, if present; folders stay."
                : "Delete only the listed old versions or backup; protected Cursor data stays."
            let detail = ([scope, finding.note]
                          + finding.entry.never.map { "Keep " + $0 }).joined(separator: " ")
            let preview = QuickCleanItem(id: "cache:" + finding.id, title: finding.entry.name, detail: detail,
                                         paths: paths, estimatedBytes: finding.bytes)
            let item = CachesConfirmation.Item(row: CacheRow(finding: finding, home: environment.homeDirectory),
                                              id: finding.id, name: finding.entry.name, leftAlone: nil)
            let work = CleanupWork(CleanupItem(name: preview.title, resources: ["cache:" + finding.id] + paths,
                                              estimatedBytes: finding.bytes)) {
                let protectedProcesses = ProcessSource {
                    let validated = await fence.validate(paths: paths)
                    var list = await originalProcesses.capture()
                    if let reason = validated.problemNow() {
                        list.failure = [list.failure, reason].compactMap { $0 }.joined(separator: " ")
                    }
                    return list
                }
                let cleaned = await ToolCacheCleaner(environment: environment, processes: protectedProcesses).clean([finding])
                return CleanupItemResult(CachesCleanReport(items: [item], result: cleaned, busy: ""))
            }
            result.append(QuickCleanOperation(kind: .toolCaches, items: [preview], work: work))
        }
        if derived.refusal == nil {
            for orphan in derived.orphans {
                let preview = QuickCleanItem(id: "derived:" + orphan.folder, title: orphan.name,
                    detail: "Orphaned build data for " + orphan.workspacePath, path: orphan.folder, estimatedBytes: orphan.bytes)
                let work = CleanupWork(CleanupItem(name: orphan.name, resources: [orphan.folder], estimatedBytes: orphan.bytes)) {
                    let validated = await fence.validate(paths: [orphan.folder])
                    if let reason = validated.problemNow() { return CleanupItemResult(.refused, detail: reason) }
                    let cleaned = await DerivedDataCleaner(environment: environment).delete([orphan])
                    if cleaned.deleted.contains(orphan) {
                        return CleanupItemResult(.cleaned, freedBytes: cleaned.freedBytes, warnings: cleaned.warnings)
                    }
                    if let refusal = cleaned.refused.first { return CleanupItemResult(.refused, detail: refusal.reason, warnings: cleaned.warnings) }
                    return CleanupItemResult(.failed, detail: cleaned.failed.first?.message ?? "Nothing was reached.", warnings: cleaned.warnings)
                }
                result.append(QuickCleanOperation(kind: .derivedData, items: [preview], work: work))
            }
        }
        let dockerConfirmation = DockerPruneConfirmation(report: docker, commandLine: nil)
        if dockerConfirmation.isAllowed, !dockerConfirmation.hasSizeEstimate || dockerConfirmation.estimatedBytes > 0 {
            let estimate = dockerConfirmation.hasSizeEstimate ? dockerConfirmation.estimatedBytes : nil
            let preview = QuickCleanItem(id: DockerSimulatorsModel.dockerResource, title: DockerPruneConfirmation.command,
                detail: "Removes stopped containers, unused networks, dangling images and unused build cache. Tagged images, running containers and volumes stay. This command's eligible contents are rechecked when it runs.", estimatedBytes: estimate)
            let resources = [DockerSimulatorsModel.dockerResource] + (docker.diskImage.map { [$0.path] } ?? [])
            let work = CleanupWork(CleanupItem(name: "Docker", resources: resources, estimatedBytes: estimate)) { [self] in
                CleanupItemResult(await dockerSimulators.runPrune())
            }
            result.append(QuickCleanOperation(kind: .docker, items: [preview], work: work))
        }
        let simulatorConfirmation = SimulatorsConfirmation(report: simulators, commandLine: nil)
        if simulatorConfirmation.isAllowed {
            let devices = simulatorConfirmation.devices
            let previews = devices.map { device in
                QuickCleanItem(id: "simulator:" + device.udid, title: device.name,
                    detail: device.runtimeName + " · " + device.udid,
                    path: environment.homeDirectory.appending(path: "Library/Developer/CoreSimulator/Devices/" + device.udid).path,
                    estimatedBytes: device.sizeBytes)
            }
            let work = CleanupWork(CleanupItem(name: "Unavailable simulators",
                resources: [DockerSimulatorsModel.simulatorsResource] + previews.compactMap(\.path),
                estimatedBytes: simulatorConfirmation.estimatedBytes, sizeEstimates: devices.map(\.sizeBytes))) { [self] in
                await protectedSimulatorDelete(devices, estimatedBytes: simulatorConfirmation.estimatedBytes,
                                               paths: previews.compactMap(\.path), fence: fence)
            }
            result.append(QuickCleanOperation(kind: .simulators, items: previews, work: work))
        }
        let mover = DownloadsMover(scanner: self.downloads.scanner, log: RemovalLog(environment: environment), trash: self.downloads.trashOperation)
        for file in downloads.eligible {
            let preview = QuickCleanItem(id: "download:" + file.path, title: file.name,
                detail: "Move to Trash; no space is freed until Trash is emptied separately.", path: file.path, estimatedBytes: file.bytes)
            let work = CleanupWork(CleanupItem(name: file.name, resources: [file.path], estimatedBytes: nil, sizeEstimates: [])) {
                let moved = await mover.move(file)
                let state: CleanupItemResult.State = switch moved.status { case .moved: .cleaned; case .refused: .refused; case .failed: .failed }
                return CleanupItemResult(state, detail: moved.reason + " · moving to Trash does not free space", warnings: moved.warnings)
            }
            result.append(QuickCleanOperation(kind: .downloads, items: [preview], work: work))
        }
        return result
    }
}
