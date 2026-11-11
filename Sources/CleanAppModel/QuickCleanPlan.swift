import CleanCore
import Foundation

@MainActor
struct QuickCleanOperation {
    let kind: QuickCleanGroup.Kind
    let items: [QuickCleanItem]
    let work: CleanupWork
    var removed: Worktree?
    var touched: Worktree?
}

@MainActor
struct QuickCleanPlan {
    let preview: QuickCleanPreview
    let operations: [QuickCleanOperation]
}

extension QuickCleanModel {
    func assemble(_ proposed: [QuickCleanOperation], warnings: [String]) -> QuickCleanPlan {
        var accepted: [QuickCleanOperation] = []
        var warnings = warnings
        let fence = sourceFence
        for operation in proposed {
            let resources = operation.work.item.resources
            let broad = [.toolCaches, .derivedData, .simulators].contains(operation.kind)
            let own = operation.removed ?? operation.touched
            if (broad || own != nil), let reason = fence.reason(paths: resources, broad: broad, own: own) {
                warnings.append("\(operation.work.item.name) was left out. " + reason)
                continue
            }
            let alreadyQueued = resources.contains { app.cleanupQueue.task(for: $0) != nil }
            let overlaps = accepted.contains { other in
                resources.contains { resource in other.work.item.resources.contains { CleanupQueue.overlaps(resource, $0) } }
            }
            if alreadyQueued || overlaps {
                warnings.append("\(operation.work.item.name) was left out because its cleanup overlaps another item or queued task.")
            } else { accepted.append(operation) }
        }
        let descriptions: [(QuickCleanGroup.Kind, String, String)] = [
            (.worktrees, "Idle worktrees", "Safe worktrees unused for at least 7 days. Branches are kept; repo folders stay."),
            (.projects, "Project build folders", "Dependency and build folders that can be downloaded or rebuilt, in projects unused for at least 7 days. Source stays."),
            (.toolCaches, "Tool caches and Cursor data", "Caches that tools download or rebuild. Data belonging to running tools and protected Cursor data stay."),
            (.derivedData, "Xcode DerivedData", "Only orphaned project build data; active projects and shared caches stay."),
            (.docker, "Docker", "One cleanup command: docker system prune -f. Running containers, tagged images and volumes stay. Docker’s disk image may shrink later."),
            (.simulators, "Unavailable simulators", "Only the listed unavailable devices. Installed runtimes and available devices stay."),
            (.downloads, "Old Downloads", "Move eligible installer and archive files added at least 30 days ago to Trash. Moving does not free space; Trash is not emptied.")
        ]
        let groups = descriptions.map { kind, title, detail in
            QuickCleanGroup(id: kind, title: title, detail: detail, items: accepted.filter { $0.kind == kind }.flatMap(\.items))
        }
        let preview = QuickCleanPreview(createdAt: app.environment.now(), groups: groups, warnings: Array(Set(warnings)).sorted())
        return QuickCleanPlan(preview: preview, operations: accepted)
    }
}
