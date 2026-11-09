import Foundation

/// The read-only side of the Project folders screen and `clean-claude projects` (PLAN §4.5): for every main
/// checkout and sibling or other worktree of a scan, `LightCleanFinder`'s candidates with their sizes, the §4.3
/// idle report and whether a process is inside. Claude and Cursor worktrees are not listed; their light-clean
/// folders are only added up for the footer. Deleting is not done here: it goes through `LightCleaner`.
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

    /// One checkout as looked at, before sizes.
    private struct Look: Sendable {
        var worktree: Worktree
        var findings: LightCleanFindings?
        var idle: IdleReport = .unknown
        var rebuildLines: [String] = []
        var problem: String?
    }

    /// Looks at the project checkouts among `worktrees` (and, with `includeLeftOut`, adds up the Claude and
    /// Cursor ones). `knownWorktrees`: every worktree of the scan, for the nested-checkout rule and for the
    /// linked worktrees inside a main checkout. `cwdIndex`: one process listing for the whole scan.
    /// `knownIdle`: idle reports already worked out, by path (the app passes its assessments').
    public func scan(
        _ worktrees: [Worktree],
        knownWorktrees: [Worktree],
        cwdIndex: ProcessCwdIndex,
        knownIdle: [String: IdleReport] = [:],
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
            await look(at: worktree, isProject: isProject, known: knownWorktrees, knownIdle: knownIdle)
        }

        let folders = looks.flatMap { $0.findings?.candidates ?? [] }.map(\.url)
        let sizes = await measure(folders) { progress(.measuring(completed: $0, total: $1)) }

        var rows: [ProjectFolders] = []
        var leftOutTotal = ProjectFoldersReport.Total(count: 0, bytes: 0)
        for look in looks {
            guard let findings = look.findings, !findings.candidates.isEmpty else { continue }
            let entries = findings.candidates.map { ProjectFolders.Folder(candidate: $0, bytes: sizes[$0.url.path]) }
            if Self.projectKinds.contains(look.worktree.kind) {
                rows.append(ProjectFolders(
                    worktree: look.worktree,
                    idle: look.idle,
                    folders: entries,
                    skipped: findings.skipped,
                    unreadable: findings.unreadable,
                    blocker: LightCleaner.inUseReason(cwdIndex, worktree: look.worktree.url),
                    rebuildLines: look.rebuildLines
                ))
            } else {
                leftOutTotal.count += 1
                leftOutTotal.bytes += entries.compactMap(\.bytes).reduce(0, +)
            }
        }
        return ProjectFoldersReport(projects: rows, leftOut: leftOutTotal, problems: looks.compactMap(\.problem))
    }

    private func look(at worktree: Worktree, isProject: Bool, known: [Worktree], knownIdle: [String: IdleReport]) async -> Look {
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
        look.idle = await idleReport(for: worktree, known: known, knownIdle: knownIdle)
        look.rebuildLines = Self.rebuildLines(in: worktree.url, candidates: findings.candidates.map(\.relativePath))
        return look
    }

    /// The checkout's idle report; for a main checkout, combined with the linked worktrees inside it (a Claude
    /// session working in `<repo>/.claude/worktrees/x` uses the repo's `node_modules` when it has none).
    public func idleReport(for worktree: Worktree, known: [Worktree], knownIdle: [String: IdleReport] = [:]) async -> IdleReport {
        let own = if let report = knownIdle[worktree.path], !worktree.isMain { report } else { await idleClock.report(for: worktree) }
        guard worktree.isMain else { return own }
        let inside = known.filter {
            !$0.isMain && !$0.isBare && !$0.isPrunable && CanonicalPath.isInside($0.url, directory: worktree.url)
        }
        var nested: [IdleReport] = []
        for linked in inside {
            if let report = knownIdle[linked.path] { nested.append(report) } else { nested.append(await idleClock.report(for: linked)) }
        }
        return Self.combined(own, nested: nested)
    }

    /// The most recent of the reports; unknown when any of them is.
    static func combined(_ own: IdleReport, nested: [IdleReport]) -> IdleReport {
        guard !nested.isEmpty else { return own }
        if own.idleDays == nil { return own }
        if nested.contains(where: { $0.idleDays == nil }) {
            var unknown = own
            unknown.idleDays = nil
            unknown.errors.append("a linked worktree inside: idle unknown")
            return unknown
        }
        return ([own] + nested).min { ($0.idleDays ?? 0) < ($1.idleDays ?? 0) } ?? own
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

    private func measure(_ folders: [URL], onFinished: @escaping @Sendable (Int, Int) -> Void) async -> [String: Int64] {
        guard let du, !folders.isEmpty else { return [:] }
        if let sizeCache { return await sizeCache.sizes(of: folders, du: du, onFinished: onFinished) }
        return await DirectorySizer(du: du).sizes(of: folders, onFinished: onFinished).sizes
    }

    private static func unique(_ worktrees: [Worktree]) -> [Worktree] {
        var seen: Set<String> = []
        return worktrees.filter { seen.insert($0.repoPath + "\u{0}" + $0.path).inserted }
    }
}
