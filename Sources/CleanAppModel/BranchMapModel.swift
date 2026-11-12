import CleanCore
import Foundation
import Observation

/// Read-only map and explicitly requested history are loaded only when their presentation needs them.
@MainActor @Observable
public final class BranchMapModel {
    public enum Layout: String, CaseIterable, Sendable { case list, timeline }
    public enum TimelineParent: Equatable { case base, branch(String) }
    public internal(set) var isOpen = false
    public var layout: Layout = .list
    public var sort: BranchMapLayout.Sort = .closest
    public internal(set) var includesRemotes = false
    public internal(set) var snapshot: BranchMapSnapshot?
    public internal(set) var family: BranchFamily?
    public internal(set) var timeline: [String: BranchTimelineEntry] = [:]
    public internal(set) var history: BranchLineage?
    public internal(set) var isLoading = false
    public internal(set) var isLoadingHistory = false
    public internal(set) var problem: String?
    public internal(set) var historyProblem: String?
    public var isFocused = false
    public var showsHistory = false
    public internal(set) var selectedBranch: String?
    @ObservationIgnored unowned let compare: CompareModel
    @ObservationIgnored let cache = BranchMap()
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var lastSelection: CompareSelection
    @ObservationIgnored var sourceRepository: String?
    @ObservationIgnored var lastBase = ""
    @ObservationIgnored var lastRepository: String?
    @ObservationIgnored var catalog: RefCatalog?

    init(compare: CompareModel) { self.compare = compare; lastSelection = compare.compare }
    public var rows: [BranchMapEntry] { BranchMapLayout.sorted(snapshot?.entries ?? [], by: sort) }
    public var collapsedSummary: String {
        if let snapshot, sourceRepository == compare.repository, snapshot.base == compare.base, snapshot.baseSHA == compare.snapshot?.range.baseSHA { return snapshot.summary }
        let count = compare.catalog?.refs.count { $0.kind == .local } ?? 0
        return count > 0 ? "\(count) branches · Open to see branch distances" : "Branch map"
    }

    public func setOpen(_ open: Bool) async {
        isOpen = open
        if open { await refresh() }
        else {
            cancelLoading()
            if showsHistory && history == nil { await refresh() }
        }
    }
    public func setIncludesRemotes(_ value: Bool) async { includesRemotes = value; if isOpen { await refresh() } }
    public func setLayout(_ value: Layout) async {
        layout = value
        if isOpen && value == .timeline && (family == nil || timeline.isEmpty) { await refresh() }
    }

    /// A hidden or unknown parent cannot be drawn as an edge from the base.
    public func timelineParent(for ref: String) -> TimelineParent? {
        guard let data = timeline[ref], data.problem == nil, data.fork != nil,
              let parent = family?.origins[ref]?.parent else { return nil }
        let base = snapshot?.base ?? ""
        let baseRef: String?
        if base == "HEAD", let repo = sourceRepository {
            baseRef = catalog?.worktrees.first { CanonicalPath.same($0.url, URL(fileURLWithPath: repo)) }
                .flatMap { $0.branch.map { "refs/heads/" + $0 } }
        } else {
            baseRef = catalog?.refs.first(where: { $0.fullName == base })?.fullName
                ?? catalog?.refs.first(where: { $0.kind == .local && $0.name == base })?.fullName
                ?? catalog?.refs.first(where: { $0.name == base })?.fullName
        }
        if parent == baseRef { return .base }
        return snapshot?.entries.contains(where: { $0.ref == parent }) == true ? .branch(parent) : nil
    }

    /// Called at the end of the existing Compare refresh, after its selected refs have settled.
    func compareRefreshed() async {
        if lastBase != compare.base || lastRepository != compare.repository {
            snapshot = nil; family = nil; timeline = [:]; catalog = nil
        }
        if lastSelection != compare.compare || lastBase != compare.base || lastRepository != compare.repository {
            lastSelection = compare.compare
            lastBase = compare.base
            lastRepository = compare.repository
            selectedBranch = nil
            history = nil
            historyProblem = nil
            showsHistory = false
            cancelLoading()
        }
        guard isOpen || showsHistory else { return }
        await refresh()
    }

    public func pick(_ ref: String, showHistory: Bool = true) async {
        selectedBranch = ref; showsHistory = showHistory; history = nil
        let selection = snapshot?.entries.first { $0.ref == ref }?.compare ?? .ref(ref)
        compare.compare = selection
        lastSelection = selection
        await compare.refresh()
    }

    public func requestHistory() async {
        showsHistory = true
        await refresh()
    }

    public var selectedRef: String? {
        guard let catalog = compare.catalog else {
            if case .ref(let ref) = compare.compare { return ref }
            return nil
        }
        return resolvedRef(selectedBranch ?? branch(for: compare.compare, catalog: catalog), catalog: catalog)
    }

    public var baseRef: String? {
        guard let catalog = compare.catalog else { return compare.base }
        return resolvedRef(compare.base, catalog: catalog)
    }

    /// Follow Git's ref spelling precedence, so a shorthand tag never highlights a same-named branch.
    private func resolvedRef(_ ref: String, catalog: RefCatalog) -> String? {
        if ref == "HEAD", let repo = compare.repository {
            return catalog.worktrees.first { CanonicalPath.same($0.url, URL(fileURLWithPath: repo)) }
                .flatMap { $0.branch.map { "refs/heads/" + $0 } } ?? ref
        }
        let spellings = [ref, "refs/" + ref, "refs/tags/" + ref, "refs/heads/" + ref,
                         "refs/remotes/" + ref, "refs/remotes/" + ref + "/HEAD"]
        for spelling in spellings where catalog.refs.contains(where: { $0.fullName == spelling }) { return spelling }
        return ref
    }

    public func refresh() async {
        guard let repo = compare.repository, let executable = compare.app.git?.executable else { return }
        generation += 1; let token = generation
        loadTask?.cancel()
        if sourceRepository != repo || snapshot?.base != compare.base {
            snapshot = nil; family = nil; history = nil
        }
        isLoading = isOpen; isLoadingHistory = showsHistory
        problem = nil; historyProblem = nil
        let base = compare.base
        let includeRemotes = includesRemotes
        let wantsMap = isOpen, wantsFamily = layout == .timeline || showsHistory
        let wantsHistory = showsHistory, wantsTimeline = layout == .timeline && isOpen
        let selection = compare.compare, requestedBranch = selectedBranch ?? selectedRef
        let lineageBase = baseRef ?? base
        let timeout = compare.app.environment.timeouts.git
        let task = Task {
            defer {
                if generation == token { isLoading = false; isLoadingHistory = false }
            }
            do {
                let git = try GitReadOnly(repository: URL(fileURLWithPath: repo), executable: executable, timeout: timeout)
                let catalog = try await RefCatalog.load(using: git)
                let resolvedBase = base.isEmpty ? catalog.defaultBase ?? "HEAD" : base
                let reader = BranchLineageReader(git: git, catalog: catalog)
                let map = wantsMap ? try await cache.load(base: resolvedBase, catalog: catalog, includeRemotes: includeRemotes, using: git) : nil
                let family = wantsFamily ? try await reader.family(base: lineageBase, includeRemotes: includeRemotes) : nil
                let timeline = wantsTimeline ? try await reader.timeline(entries: map?.entries ?? [], origins: family?.origins ?? [:]) : [:]
                try Task.checkCancellation()
                guard generation == token else { return }
                self.catalog = catalog; sourceRepository = repo
                if let map { snapshot = map }
                self.family = family; self.timeline = timeline
                if wantsHistory {
                    let branch = requestedBranch ?? branch(for: selection, catalog: catalog)
                    selectedBranch = branch
                    do {
                        let history = try await reader.load(branch: branch, base: lineageBase, origins: family?.origins)
                        try Task.checkCancellation()
                        if generation == token { self.history = history }
                    } catch is CancellationError {} catch {
                        if generation == token { history = nil; historyProblem = "Couldn't read this branch's history. \(error)" }
                    }
                }
            } catch is CancellationError {} catch {
                if generation == token { problem = "Couldn't read the branch map. \(error)" }
            }
        }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func cancelLoading() {
        generation += 1; loadTask?.cancel(); loadTask = nil
        isLoading = false; isLoadingHistory = false
    }

    private func branch(for selection: CompareSelection, catalog: RefCatalog) -> String {
        switch selection {
        case .ref(let ref): return ref
        case .worktree(let path):
            if let worktree = catalog.worktrees.first(where: { CanonicalPath.same($0.url, URL(fileURLWithPath: path)) }) {
                return worktree.branch.map { "refs/heads/" + $0 } ?? "worktree:" + worktree.path
            }
            return "HEAD"
        }
    }
}
