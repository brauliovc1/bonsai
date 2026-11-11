@testable import CleanAppModel
@testable import CleanCore
import Foundation

/// Display-only samples. No file operation uses these synthetic paths.
enum PresentationFixtures {
    static func worktree(_ index: Int) -> Worktree {
        Worktree(path: "/tmp/presentation/repo-task-\(index)", repoPath: "/tmp/presentation/repo", head: "abc123", branch: "task-\(index)", isMain: false, kind: .sibling)
    }
    static func removal(_ count: Int) -> RemovalConfirmation {
        RemovalConfirmation(items: (0..<count).map { index in
            RemovalConfirmation.Item(assessment: WorktreeAssessment(worktree: worktree(index), idle: .idle(days: 45), safety: SafetyReport(blockers: [], notes: [], autoBlockers: []), estimatedBytes: 1_000_000))
        })
    }
    static func dependencies(_ count: Int) -> LightCleanConfirmation {
        LightCleanConfirmation(items: (0..<count).map { index in
            let tree = worktree(index)
            let folder = LightCleanCandidate(worktreePath: tree.path, relativePath: "node_modules", name: "node_modules", estimatedBytes: 1_000_000, packageClones: [])
            return LightCleanConfirmation.Item(worktree: tree, findings: LightCleanFindings(worktree: tree, candidates: [folder]), blocker: nil)
        })
    }
    static func projects(_ count: Int) -> ProjectsConfirmation {
        ProjectsConfirmation(items: dependencies(count).items.map {
            ProjectsConfirmation.Item(lightClean: $0, idle: .idle(days: 45), threshold: 30, rebuildLines: ["npm install"])
        })
    }
    static func derivedData(_ count: Int) -> DerivedDataConfirmation {
        DerivedDataConfirmation(root: "/tmp/presentation/DerivedData", refusal: nil, items: (0..<count).map { index in
            let orphan = OrphanedDerivedData(root: "/tmp/presentation/DerivedData", name: "App-\(index)", workspacePath: "/Users/gone/App.xcodeproj", bytes: 1_000_000)
            return DerivedDataConfirmation.Item(folder: orphan.folder, name: orphan.name, state: .orphaned, workspacePath: orphan.workspacePath, bytes: orphan.bytes, orphan: orphan, leftAloneReason: nil)
        })
    }
    static func simulators(_ count: Int) -> SimulatorsConfirmation {
        SimulatorsConfirmation(report: SimulatorReport(state: .available, unavailableDevices: (0..<count).map {
            SimulatorDevice(name: "iPhone \($0 + 14)", udid: "device-\($0)", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", sizeBytes: 1_000_000)
        }), commandLine: nil)
    }
    static func caches(_ count: Int) -> CachesConfirmation {
        let entries = Array(ToolCacheCatalog.entries.prefix(count))
        return CachesConfirmation(items: entries.map { entry in
            let finding = ToolCacheFinding(inspection: ToolCacheInspection(entry: entry, present: [], removals: ["/tmp/presentation/cache"]), bytes: 1_000_000)
            return CachesConfirmation.Item(row: CacheRow(finding: finding, home: URL(fileURLWithPath: "/tmp/presentation")), id: entry.id, name: entry.name, leftAlone: nil)
        })
    }
    static func entry(_ index: Int = 0, action: RemovalAction = .worktreeRemove) -> RemovalLogEntry {
        RemovalLogEntry(date: Date(timeIntervalSince1970: 1_794_288_000 - Double(index * 86_400)), mode: .manual, action: action, repoPath: worktree(index).repoPath, path: worktree(index).path, branch: worktree(index).branch, estimatedBytes: 1_000_000, freedBytes: 900_000)
    }
}
