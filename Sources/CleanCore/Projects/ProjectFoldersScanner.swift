import Foundation

/// The read-only side of the Project folders screen and `clean-claude projects` (PLAN §4.5): for every main
/// checkout and sibling or other worktree of a scan, `LightCleanFinder`'s candidates with their sizes, the §4.3
/// idle report read now and whether a process works there. Claude and Cursor worktrees are not listed; their
/// light-clean folders are only added up for the footer. Deleting is not done here: it goes through `LightCleaner`.
public struct ProjectFoldersScanner: Sendable {
    /// The kinds listed as projects.
    public static let projectKinds: Set<WorktreeKind> = [.main, .sibling, .other]
    /// The kinds left out (and counted for the footer).
    public static let leftOutKinds: Set<WorktreeKind> = [.claude, .cursor]

    public enum Progress: Sendable, Hashable {
        case looking(completed: Int, total: Int)
        case measuring(completed: Int, total: Int)
    }

    public var git: Git
    public var finder: LightCleanFinder
    public var idleClock: IdleClock
    public var du: URL?
    /// `sizes.json`; nil measures every folder and writes nothing (the CLI).
    public var sizeCache: FolderSizeCache?
    /// Checkouts looked at the same time.
    public var maxConcurrent: Int

    public init(git: Git, environment: CleanEnvironment, sizeCache: FolderSizeCache? = nil, maxConcurrent: Int = 2) {
        self.git = git
        self.finder = LightCleanFinder(git: git, du: environment.tools.du)
        self.idleClock = IdleClock(git: git, claudeConfigDirectory: environment.claudeConfigDirectory, now: environment.now)
        self.du = environment.tools.du
        self.sizeCache = sizeCache
        self.maxConcurrent = maxConcurrent
    }

    /// One checkout as looked at, before idle days and sizes.
    private struct Look: Sendable {
        var worktree: Worktree
        var findings: LightCleanFindings?
        var rebuildLines: [String] = []
        var problem: String?
    }

    /// Looks at the project checkouts among `worktrees` (and, with `includeLeftOut`, adds up the Claude and
    /// Cursor ones). `knownWorktrees`: every worktree of the scan, for the nested-checkout rule and a main
    /// checkout's `LinkedWorktrees`. `cwdIndex`: one process listing for the whole scan. `log`: the removal log,
    /// so `sizes.json` entries of checkouts cleaned since they were measured are measured again.
    public func scan(
        _ worktrees: [Worktree],
        knownWorktrees: [Worktree],
        cwdIndex: ProcessCwdIndex,
        log: [RemovalLogEntry] = [],
        includeLeftOut: Bool = true,
        progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async -> ProjectFoldersReport {
        let usable = Self.unique(worktrees.filter { !$0.isBare && !$0.isPrunable })
        let projects = usable.filter { Self.projectKinds.contains($0.kind) }
        let leftOut = includeLeftOut ? usable.filter { Self.leftOutKinds.contains($0.kind) } : []
        let targets = projects.map { ($0, true) } + leftOut.map { ($0, false) }
        let total = targets.count
        let looks = await BoundedConcurrency.map(targets, limit: maxConcurrent, onCompletion: {
            progress(.looking(completed: $0, total: total))
        }) { worktree, isProject in
            await look(at: worktree, isProject: isProject, known: knownWorktrees)
        }

        // Idle days, read now, once per worktree: each listed project's own and its linked worktrees'.
        let listed = looks.filter { Self.projectKinds.contains($0.worktree.kind) && !($0.findings?.candidates.isEmpty ?? true) }
        var linked: [String: [Worktree]] = [:]
        for look in listed { linked[Self.key(look.worktree)] = LinkedWorktrees.of(look.worktree, in: knownWorktrees) }
        let clocked = Self.unique(listed.map(\.worktree) + linked.values.flatMap { $0 })
        let reports = await BoundedConcurrency.map(clocked, limit: maxConcurrent) { await idleClock.report(for: $0) }
        let idle = Dictionary(zip(clocked.map(Self.key), reports)) { first, _ in first }

        let folders = looks.flatMap { look in
            (look.findings?.candidates ?? []).map { FolderSizeCache.Folder(url: $0.url, checkout: look.worktree.path) }
        }
        let sizes = await measure(folders, log: log) { progress(.measuring(completed: $0, total: $1)) }

        var rows: [ProjectFolders] = []
        var leftOutTotal = ProjectFoldersReport.Total(count: 0, bytes: 0)
        for look in looks {
            guard let findings = look.findings, !findings.candidates.isEmpty else { continue }
            let entries = findings.candidates.map { ProjectFolders.Folder(candidate: $0, bytes: sizes[$0.url.path]) }
            guard Self.projectKinds.contains(look.worktree.kind) else {
                leftOutTotal.count += 1
                leftOutTotal.bytes += entries.compactMap(\.bytes).reduce(0, +)
                continue
            }
            let others = (linked[Self.key(look.worktree)] ?? []).map { idle[Self.key($0)] ?? .unknown }
            rows.append(ProjectFolders(
                worktree: look.worktree,
                idle: Self.combined(idle[Self.key(look.worktree)] ?? .unknown, linked: others),
                folders: entries,
                skipped: findings.skipped,
                unreadable: findings.unreadable,
                blocker: LightCleaner.inUseReason(cwdIndex, worktree: look.worktree.url),
                linkedInUse: LinkedWorktrees.processes(of: look.worktree, in: knownWorktrees, index: cwdIndex),
                rebuildLines: look.rebuildLines
            ))
        }
        return ProjectFoldersReport(projects: rows, leftOut: leftOutTotal, problems: looks.compactMap(\.problem))
    }

    private func look(at worktree: Worktree, isProject: Bool, known: [Worktree]) async -> Look {
        var look = Look(worktree: worktree)
        // A stale record: the folder is another repo's, so nothing read there is about this record.
        if let blocker = await SafetyCheck(git: git).identityBlocker(of: worktree) {
            look.problem = "\(worktree.path): \(blocker.sentence)"
            return look
        }
        let findings = await finder.candidates(in: worktree, knownWorktrees: known, measureSizes: false)
        if let problem = findings.problem {
            look.problem = "\(worktree.path): \(problem)"
            return look
        }
        look.findings = findings
        guard isProject, !findings.candidates.isEmpty else { return look }
        look.rebuildLines = Self.rebuildLines(in: worktree.url, candidates: findings.candidates.map(\.relativePath))
        return look
    }

    /// The checkout's idle report read now; for a main checkout, combined with its `LinkedWorktrees`'.
    public func idleReport(for worktree: Worktree, known: [Worktree]) async -> IdleReport {
        let own = await idleClock.report(for: worktree)
        var linked: [IdleReport] = []
        for other in LinkedWorktrees.of(worktree, in: known) {
            linked.append(await idleClock.report(for: other))
        }
        return Self.combined(own, linked: linked)
    }

    /// The most recent of the reports; unknown when any of them is.
    static func combined(_ own: IdleReport, linked: [IdleReport]) -> IdleReport {
        guard !linked.isEmpty else { return own }
        if own.idleDays == nil { return own }
        if linked.contains(where: { $0.idleDays == nil }) {
            var unknown = own
            unknown.idleDays = nil
            unknown.errors.append("a linked worktree: idle unknown")
            return unknown
        }
        return ([own] + linked).min { ($0.idleDays ?? 0) < ($1.idleDays ?? 0) } ?? own
    }

    /// `RebuildHint`'s lines from the names in the checkout root and in each candidate's parent folder.
    public static func rebuildLines(in root: URL, candidates: [String]) -> [String] {
        var entries: [String: [String]] = [:]
        for folder in RebuildHint.folders(for: candidates) {
            let path = folder.isEmpty ? root.path : root.path + "/" + folder
            entries[folder] = DirectoryEntries.read(path)?.map(\.name) ?? []
        }
        return RebuildHint.lines(candidates: candidates, entries: entries)
    }

    private func measure(
        _ folders: [FolderSizeCache.Folder],
        log: [RemovalLogEntry],
        onFinished: @escaping @Sendable (Int, Int) -> Void
    ) async -> [String: Int64] {
        guard let du, !folders.isEmpty else { return [:] }
        if let sizeCache { return await sizeCache.sizes(of: folders, du: du, log: log, onFinished: onFinished) }
        return await DirectorySizer(du: du).sizes(of: folders.map(\.url), onFinished: onFinished).sizes
    }

    private static func key(_ worktree: Worktree) -> String {
        worktree.repoPath + "\u{0}" + worktree.path
    }

    private static func unique(_ worktrees: [Worktree]) -> [Worktree] {
        var seen: Set<String> = []
        return worktrees.filter { seen.insert(key($0)).inserted }
    }
}
