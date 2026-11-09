import Foundation

/// What cleaning one catalog entry would delete right now, and whether it may (PLAN §4.6), against one process
/// list: the path rules for every path, then the Cursor rules, then the owners. The scanner shows it; the
/// cleaner makes a new one right before each entry and deletes only what that one allows.
struct ToolCacheInspection: Sendable, Hashable {
    /// One of the entry's paths that exists.
    struct Present: Sendable, Hashable {
        var relative: String
        var path: String
        /// What lstat saw when the path rules passed; nil when they refused it.
        var identity: FileIdentity?
    }

    let entry: ToolCacheEntry
    var present: [Present]
    /// Absolute paths of what goes: each present target folder (its children go, not the folder) for
    /// `.contents`, the version folders, or the backup file.
    var removals: [String] = []
    var kept: [CursorAgentVersions.Kept] = []
    var runningOwners: [String] = []
    /// Why the entry may not be cleaned now; nil when it may, and for a display-only entry.
    var refusal: String?
    /// Every path passed the path rules, so measuring stays inside the entry's own folders.
    var pathsPassed = true
    /// Nothing inside the targets to delete.
    var isEmpty = false
    var backupDate: Date?

    /// nil when none of the entry's paths exists (the entry is not shown).
    static func inspect(_ entry: ToolCacheEntry, home: URL, processes: ProcessList, now: Date) -> ToolCacheInspection? {
        var present: [Present] = []
        var pathRefusal: String?
        for relative in entry.paths {
            let path = home.standardized.path + "/" + relative
            switch ToolCachePathCheck.check(relative, home: home, expect: entry.pathKind) {
            case .missing:
                continue
            case .passed(let identity):
                present.append(Present(relative: relative, path: path, identity: identity))
            case .refused(let why):
                present.append(Present(relative: relative, path: path, identity: nil))
                pathRefusal = pathRefusal ?? why
            }
        }
        guard !present.isEmpty else { return nil }
        var inspection = ToolCacheInspection(entry: entry, present: present)
        inspection.pathsPassed = pathRefusal == nil
        guard entry.isCleanable else { return inspection }
        if let pathRefusal {
            inspection.refusal = pathRefusal
            return inspection
        }
        inspection.applyRules(home: home, now: now)
        inspection.applyOwners(processes)
        return inspection
    }

    private mutating func applyRules(home: URL, now: Date) {
        switch entry.deletion {
        case .contents:
            removals = present.map(\.path)
            isEmpty = present.allSatisfy { DirectoryEntries.read($0.path)?.isEmpty ?? false }
        case .cursorAgentVersions:
            switch CursorAgentVersions.resolve(home: home) {
            case .refused(let why):
                refusal = why
            case .resolved(let versions):
                let folder = home.standardized.path + "/" + CursorAgentVersions.versionsPath
                removals = versions.removable.map { folder + "/" + $0 }
                kept = versions.kept
                isEmpty = removals.isEmpty
            }
        case .cursorStateBackup:
            switch CursorStateBackup.decide(home: home, now: now) {
            case .refused(let why, let date):
                refusal = why
                backupDate = date
            case .allowed(let date):
                removals = present.map(\.path)
                backupDate = date
            }
        case .none:
            break
        }
    }

    /// A running owner refuses the entry, unless a rule already did (quitting the tool wouldn't help then).
    private mutating func applyOwners(_ processes: ProcessList) {
        guard let running = processes.runningOwners(entry.owners, mentioning: present.map(\.path)) else {
            let names = ToolOwner.list(entry.owners.map(\.name), conjunction: "or")
            refusal = refusal ?? "can't tell whether \(names) is running: \(processes.failure ?? "ps failed")"
            return
        }
        runningOwners = running
        if !running.isEmpty { refusal = refusal ?? ToolOwner.quitSentence(running) }
    }

    /// What the scanner measures: what would go, or, for an entry it can't clean now, its present paths. Nothing
    /// when a path rule refused (a symlink would lead the measurement elsewhere).
    var measuredPaths: [String] {
        guard pathsPassed else { return [] }
        if entry.isCleanable, refusal == nil || !removals.isEmpty { return removals }
        if case .cursorAgentVersions = entry.deletion { return [] }
        return present.map(\.path)
    }
}
