import CleanCore
import Foundation
import Observation

/// Read-only review state. `configure` is also the entry point for the branch map and history panel.
@MainActor @Observable
public final class CompareModel {
    public let app: AppModel
    public var repository: String?
    public var base = ""
    public var compare: CompareSelection = .ref("HEAD")
    public internal(set) var catalog: RefCatalog?
    public internal(set) var snapshot: CompareSnapshot?
    public internal(set) var files: [CompareFile] = []
    public internal(set) var selectedPath: String?
    public internal(set) var document: DiffDocument?
    public internal(set) var patchText = ""
    public internal(set) var problem: String?
    public internal(set) var isLoading = false
    public internal(set) var isLoadingDiff = false
    public var sideBySide = false
    public var ignoresWhitespace = false
    public var filter = ""
    public var flatList = false
    public var showsGenerated = false
    public var collapsedFolders: Set<String> = []
    public var showsCommits = false
    public internal(set) var selectedCommit: String?
    public internal(set) var viewed: Set<String> = []
    public var expandedLargeFiles: Set<String> = []
    public internal(set) var contextLines = 3
    @ObservationIgnored var reader: CompareReader?
    @ObservationIgnored var activeRange: CompareRange?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var fileGeneration = 0
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var diffTask: Task<Void, Never>?
    @ObservationIgnored var prefetchTask: Task<Void, Never>?
    @ObservationIgnored var cache: [String: (Data, DiffDocument)] = [:]

    public init(app: AppModel) { self.app = app }

    public var repositories: [String] { Array(Set(app.scan?.worktrees.map(\.repoPath) ?? [])).sorted() }
    public var visibleFiles: [CompareFile] {
        files.filter { file in
            (filter.isEmpty || file.path.localizedCaseInsensitiveContains(filter))
                && (showsGenerated || !file.isGenerated || !filter.isEmpty)
                && (flatList || !collapsedFolders.contains { file.path.hasPrefix($0 + "/") })
        }
    }
    public var selectedFile: CompareFile? { files.first { $0.path == selectedPath } }
    public var generatedCount: Int { files.filter(\.isGenerated).count }
    public var viewedCount: Int { files.filter { viewed.contains(viewedKey($0.path)) }.count }
    public var fetchText: String {
        guard let date = catalog?.lastFetch else { return "As of the last fetch · Never fetched" }
        return "As of the last fetch, \(DisplayText.timeAgo(date, now: app.environment.now()))"
    }
    public var diffIsCollapsed: Bool {
        guard let file = selectedFile else { return false }
        return (file.isGenerated || file.isLarge) && !expandedLargeFiles.contains(file.path)
    }

    public func configure(repo: String, base: String? = nil, compare: CompareSelection? = nil) async {
        repository = repo
        self.base = base ?? ""
        self.compare = compare ?? .ref("HEAD")
        await refresh()
    }

    public func loadIfNeeded() async {
        if repository == nil, let first = repositories.first { await configure(repo: first) }
    }

    public func refresh() async {
        generation += 1
        let token = generation
        loadTask?.cancel(); diffTask?.cancel(); prefetchTask?.cancel()
        fileGeneration += 1
        snapshot = nil; document = nil; files = []; selectedPath = nil; selectedCommit = nil
        cache = [:]; problem = nil; isLoading = true; isLoadingDiff = false
        let repo = repository; let chosenBase = base; let chosenCompare = compare
        let task = Task {
            defer { if generation == token { isLoading = false } }
            do {
                guard let repo, let executable = app.git?.executable else { throw CompareError("Choose a repo and install Git to compare branches.") }
                let git = try GitReadOnly(repository: URL(fileURLWithPath: repo), executable: executable, timeout: app.environment.timeouts.git)
                let freshCatalog = try await RefCatalog.load(using: git)
                let resolvedBase = chosenBase.isEmpty ? freshCatalog.defaultBase ?? "HEAD" : chosenBase
                let freshReader = CompareReader(git: git)
                let fresh = try await freshReader.load(base: resolvedBase, compare: chosenCompare)
                try Task.checkCancellation()
                guard token == generation else { return }
                catalog = freshCatalog; base = resolvedBase; reader = freshReader
                snapshot = fresh; activeRange = fresh.range; files = fresh.files
                if let first = visibleFiles.first { await selectFile(first.path) }
            } catch is CancellationError {} catch {
                if token == generation { problem = "Couldn't compare these branches. \(error)" }
            }
        }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    public func swap() async {
        let oldBase = base
        switch compare {
        case .ref(let name): base = name; compare = .ref(oldBase)
        case .worktree: base = snapshot?.range.compareSHA ?? "HEAD"; compare = .ref(oldBase)
        }
        await refresh()
    }

    public func toggleViewed(_ path: String) {
        let key = viewedKey(path)
        if !viewed.insert(key).inserted { viewed.remove(key) }
    }
    public func isViewed(_ path: String) -> Bool { viewed.contains(viewedKey(path)) }
    func viewedKey(_ path: String) -> String { "\(repository ?? "")\0\(base)\0\(compare)\0\(path)" }

    public func moveFile(_ delta: Int) async {
        let shown = visibleFiles
        guard !shown.isEmpty else { return }
        let index = shown.firstIndex { $0.path == selectedPath } ?? -1
        await selectFile(shown[max(0, min(shown.count - 1, index + delta))].path)
    }
}
