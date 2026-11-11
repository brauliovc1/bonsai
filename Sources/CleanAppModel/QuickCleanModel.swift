import CleanCore
import Foundation
import Observation

@MainActor @Observable
public final class QuickCleanModel {
    public var isPresented = false { didSet { if !isPresented { invalidate() } } }
    public private(set) var isPreparing = false
    public private(set) var preview: QuickCleanPreview?
    public private(set) var problem: String?
    @ObservationIgnored let app: AppModel
    @ObservationIgnored let worktrees: WorktreesModel
    @ObservationIgnored let projects: ProjectsModel
    @ObservationIgnored let caches: CachesModel
    @ObservationIgnored let derivedData: DerivedDataModel
    @ObservationIgnored let dockerSimulators: DockerSimulatorsModel
    @ObservationIgnored let downloads: DownloadsTrashModel
    @ObservationIgnored var plan: QuickCleanPlan?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var preparation: Task<Void, Never>?
    @ObservationIgnored var configureRemover: @Sendable (inout Remover) -> Void = { _ in }
    @ObservationIgnored var configureLightCleaner: @Sendable (inout LightCleaner) -> Void = { _ in }
    @ObservationIgnored var beforePublish: @MainActor () async -> Void = {}

    public init(app: AppModel, worktrees: WorktreesModel, projects: ProjectsModel, caches: CachesModel,
                derivedData: DerivedDataModel, dockerSimulators: DockerSimulatorsModel, downloads: DownloadsTrashModel) {
        self.app = app; self.worktrees = worktrees; self.projects = projects; self.caches = caches
        self.derivedData = derivedData; self.dockerSimulators = dockerSimulators; self.downloads = downloads
    }

    public var confirmationDisabledReason: String? {
        guard isPresented else { return "Open a fresh Quick clean preview first." }
        guard !app.isQuitting else { return "Bonsai is quitting; no new cleanup can be queued." }
        guard !isPreparing else { return "Wait for the fresh preview to finish." }
        guard let plan, preview?.id == plan.preview.id else { return "This preview is no longer available. Refresh it to continue." }
        guard !plan.operations.isEmpty else { return "Nothing is ready to clean." }
        guard plan.operations.allSatisfy({ operation in
            operation.work.item.resources.allSatisfy { app.cleanupQueue.task(for: $0) == nil }
        }) else { return "Another cleanup includes one of these items. Refresh the preview when it finishes." }
        return nil
    }
    public var canConfirm: Bool { confirmationDisabledReason == nil }

    public func begin() async {
        invalidate()
        guard !app.isQuitting else { return }
        isPresented = true; isPreparing = true; problem = nil
        let token = generation
        let task = Task { [self] in
            defer { if token == generation { isPreparing = false } }
            let prepared = await prepare()
            await beforePublish()
            guard token == generation, isPresented, !Task.isCancelled, !app.isQuitting else { return }
            plan = prepared; preview = prepared.preview; isPreparing = false
        }
        preparation = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    public func dismiss() { isPresented = false }

    @discardableResult
    public func confirm() -> CleanupTask? {
        guard canConfirm, let plan else {
            if isPresented && !isPreparing { problem = "The preview is no longer available or an item is already queued. Refresh Quick clean." }
            return nil
        }
        let operations = plan.operations
        let task = app.cleanupQueue.enqueue(title: "Quick clean", unit: "steps", work: operations.map(\.work)) { [self] task in
            let cleaned = zip(operations, task.items).filter { $0.1.result?.state == .cleaned }.map(\.0)
            await app.cleanupFinished(touched: cleaned.compactMap(\.touched), removed: cleaned.compactMap(\.removed))
            let refreshes: [@MainActor () async -> Void] = [
                { await self.projects.refresh() }, { await self.caches.refresh() }, { await self.derivedData.refresh() },
                { await self.dockerSimulators.refresh() }, { await self.downloads.refresh() }
            ]
            for refresh in refreshes {
                guard !app.isQuitting else { break }
                await refresh()
            }
        }
        guard let task else { problem = "An item is already queued, so nothing was added. Refresh Quick clean."; return nil }
        dismiss()
        return task
    }

    private func invalidate() {
        generation += 1; preparation?.cancel(); preparation = nil
        plan = nil; preview = nil; isPreparing = false
    }
}
