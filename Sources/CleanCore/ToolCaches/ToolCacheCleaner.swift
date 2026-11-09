import Foundation

/// Cleans the tool-cache entries a person confirmed (PLAN §4.6). Manual only.
///
/// For each entry in turn: it must be a cleanable catalog entry the scan found ready; then a fresh process list
/// and a fresh inspection (path rules from the home folder down, the Cursor keep set or backup rule, the owners):
/// any refusal skips the entry and the run goes on with the next. Then the entry's items go one by one: the
/// top-level children of each target folder (the folder stays; `removeItem` on a symlink child removes only the
/// link), the version folders the scan listed and the fresh keep set still allows, or the backup. Right before
/// each item the target is lstat'ed again from the home folder down and must be the same folder (or file) the
/// inspection saw. Free space is read before and after each entry, and its `cacheClean` log entry is written
/// right after it.
///
/// The caller holds `cleanup.lock` for the whole call, like every other cleanup: the app inside its cleanup
/// guard (`AppModel.cleaningUp`), the CLI through `--yes` (`CommandContext.holdCleanupLock`).
public struct ToolCacheCleaner: Sendable {
    public var homeDirectory: URL
    public var log: RemovalLog
    public var now: @Sendable () -> Date
    /// A fresh process list before each entry.
    public var processes: ProcessSource
    var catalog = ToolCacheCatalog.entries
    /// Test seam: the free space of the home folder's volume (default: read from the volume).
    var freeSpace: FreeSpaceProbe?
    /// Test seam: runs before an entry's fresh process list and inspection.
    var beforeEntry: @Sendable (ToolCacheEntry) async -> Void = { _ in }
    /// Test seam: runs right before an item's last check.
    var beforeItem: @Sendable (String) -> Void = { _ in }

    public init(homeDirectory: URL, log: RemovalLog, processes: ProcessSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.homeDirectory = homeDirectory
        self.log = log
        self.processes = processes
        self.now = now
    }

    public init(environment: CleanEnvironment, processes: ProcessSource = .live()) {
        self.init(homeDirectory: environment.homeDirectory, log: RemovalLog(environment: environment), processes: processes, now: environment.now)
    }

    /// `shouldContinue` is asked before each entry (the app stops when it quits); a no refuses the rest.
    public func clean(
        _ confirmed: [ToolCacheFinding],
        shouldContinue: @Sendable () async -> Bool = { true }
    ) async -> ToolCacheCleanResult {
        var result = ToolCacheCleanResult()
        var seen = Set<String>()
        let queue = confirmed.filter { seen.insert($0.id).inserted }
        var freed: [Int64?] = []
        for (position, finding) in queue.enumerated() {
            guard await shouldContinue() else {
                result.refused += queue[position...].map { refusal($0, "the cleanup was stopped before its turn") }
                break
            }
            switch await prepare(finding) {
            case .refused(let reason):
                result.refused.append(refusal(finding, reason))
            case .go(let entry, let inspection, let removals):
                let probe = freeSpace ?? .volume(containing: homeDirectory)
                let before = probe.availableBytes()
                let outcome = remove(entry, inspection: inspection, removals: removals)
                let after = probe.availableBytes()
                let bytes = before.flatMap { before in after.map { max(0, $0 - before) } }
                freed.append(bytes)
                let cleaned = ToolCacheCleanResult.Cleaned(
                    id: entry.id, name: entry.name, removedCount: outcome.removed.count,
                    estimatedBytes: finding.bytes, freedBytes: bytes, failures: outcome.failures
                )
                result.cleaned.append(cleaned)
                record(logEntry(for: entry, inspection: inspection, outcome: outcome, cleaned: cleaned), in: &result)
            }
        }
        if !freed.isEmpty, freed.allSatisfy({ $0 != nil }) {
            result.freedBytes = freed.compactMap { $0 }.reduce(0, +)
        }
        return result
    }

    private enum Preparation {
        case refused(String)
        case go(ToolCacheEntry, ToolCacheInspection, [String])
    }

    /// The checks before an entry's first item: catalog, verdict, a fresh process list and inspection.
    private func prepare(_ finding: ToolCacheFinding) async -> Preparation {
        guard let entry = catalog.first(where: { $0.id == finding.id }), entry == finding.entry, entry.isCleanable else {
            return .refused("\(finding.id) is not a cleanable catalog entry")
        }
        guard finding.isReady else {
            return .refused(finding.verdict.reason ?? "it was \(finding.verdict.label) when it was confirmed")
        }
        await beforeEntry(entry)
        let list = await processes.capture()
        guard let fresh = ToolCacheInspection.inspect(entry, home: homeDirectory, processes: list, now: now()) else {
            return .refused("it no longer exists")
        }
        if let refusal = fresh.refusal { return .refused(refusal) }
        if fresh.isEmpty { return .refused("there is nothing left in it to clean") }
        switch entry.deletion {
        case .cursorAgentVersions:
            // Only versions the person saw in the confirmation, and only those the fresh keep set still allows.
            let removals = fresh.removals.filter(finding.removals.contains)
            guard !removals.isEmpty else { return .refused("the versions it would remove changed since it was confirmed") }
            return .go(entry, fresh, removals)
        case .cursorStateBackup:
            guard let path = fresh.present.first, finding.identities[path.path] == path.identity else {
                return .refused("the backup was replaced since it was confirmed")
            }
            return .go(entry, fresh, fresh.removals)
        case .contents, .none:
            return .go(entry, fresh, fresh.removals)
        }
    }

    private func refusal(_ finding: ToolCacheFinding, _ reason: String) -> ToolCacheCleanResult.Refused {
        ToolCacheCleanResult.Refused(id: finding.id, name: finding.entry.name, reason: reason)
    }

    private func record(_ entry: RemovalLogEntry, in result: inout ToolCacheCleanResult) {
        result.entries.append(entry)
        do {
            try log.append(entry)
        } catch {
            result.logged = false
            result.warnings.append("\(entry.repoPath) (\(entry.path)) was not logged: \(error)")
        }
    }
}
