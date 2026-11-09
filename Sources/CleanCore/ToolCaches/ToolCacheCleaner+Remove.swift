import Foundation

extension ToolCacheCleaner {
    /// What one entry's removal did.
    struct Outcome {
        /// The names of what went: children, version folders or the backup.
        var removed: [String] = []
        var failures: [String] = []
    }

    /// Removes the entry's items one by one, each after a last look at its target. A target that changed stops
    /// the entry there.
    func remove(_ entry: ToolCacheEntry, inspection: ToolCacheInspection, removals: [String]) -> Outcome {
        var outcome = Outcome()
        switch entry.deletion {
        case .contents:
            for target in inspection.present {
                guard let children = DirectoryEntries.read(target.path) else {
                    outcome.failures.append("\(shown(target.path)) can't be read")
                    continue
                }
                for child in children.sorted(by: { $0.name < $1.name }) {
                    let path = target.path + "/" + child.name
                    beforeItem(path)
                    // Nothing runs between this last look at the target folder and removeItem.
                    if let problem = changed(target, entry) {
                        outcome.failures.append("stopped before \(shown(path)): \(problem)")
                        return outcome
                    }
                    removeItem(path, into: &outcome)
                }
            }
        case .cursorAgentVersions:
            guard let versions = inspection.present.first else { return outcome }
            for path in removals {
                beforeItem(path)
                if let problem = changed(versions, entry) {
                    outcome.failures.append("stopped before \(shown(path)): \(problem)")
                    return outcome
                }
                guard DirectoryEntries.kind(ofItemAt: path) == .directory else {
                    outcome.failures.append("\(shown(path)) is no longer a folder")
                    continue
                }
                removeItem(path, into: &outcome)
            }
        case .cursorStateBackup:
            guard let backup = inspection.present.first else { return outcome }
            beforeItem(backup.path)
            if let problem = changed(backup, entry) {
                outcome.failures.append("left alone: \(problem)")
            } else if case .refused(let why, _) = CursorStateBackup.decide(home: homeDirectory, now: now()) {
                outcome.failures.append("left alone: \(why)")
            } else {
                removeItem(backup.path, into: &outcome)
            }
        case .none:
            break
        }
        return outcome
    }

    /// Why `present` is no longer the folder (or file) the inspection saw; nil when it still is.
    func changed(_ present: ToolCacheInspection.Present, _ entry: ToolCacheEntry) -> String? {
        switch ToolCachePathCheck.check(present.relative, home: homeDirectory, expect: entry.pathKind) {
        case .missing: "\(shown(present.path)) is gone"
        case .refused(let why): why
        case .passed(let identity): identity == present.identity ? nil : "\(shown(present.path)) was replaced"
        }
    }

    private func removeItem(_ path: String, into outcome: inout Outcome) {
        do {
            try FileManager.default.removeItem(atPath: path)
            outcome.removed.append((path as NSString).lastPathComponent)
        } catch {
            outcome.failures.append("\(shown(path)): \(error.localizedDescription)")
        }
    }

    func shown(_ path: String) -> String {
        TildePath.abbreviate(path, home: homeDirectory)
    }

    /// One entry per cleaned catalog entry: `repoPath` is the entry id, `path` the folder it cleaned.
    func logEntry(
        for entry: ToolCacheEntry,
        inspection: ToolCacheInspection,
        outcome: Outcome,
        cleaned: ToolCacheCleanResult.Cleaned
    ) -> RemovalLogEntry {
        let folders = inspection.present.map(\.path)
        var notes: [String]
        switch entry.deletion {
        case .cursorAgentVersions:
            notes = ["removed versions " + (outcome.removed.isEmpty ? "none" : outcome.removed.joined(separator: ", "))]
            if !inspection.kept.isEmpty {
                notes.append("kept " + inspection.kept.map { "\($0.name) (\($0.reason))" }.joined(separator: ", "))
            }
        case .cursorStateBackup:
            notes = [outcome.removed.isEmpty ? "removed nothing" : "removed " + CursorStateBackup.note(date: inspection.backupDate)]
        case .contents, .none:
            let count = outcome.removed.count
            notes = ["removed \(count) \(count == 1 ? "item" : "items") from " + folders.map(shown).joined(separator: ", ")]
        }
        notes += outcome.failures.prefix(10).map { "could not remove \($0)" }
        if outcome.failures.count > 10 { notes.append("and \(outcome.failures.count - 10) more could not be removed") }
        return RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: .cacheClean,
            repoPath: entry.id,
            path: Self.folder(of: folders),
            estimatedBytes: cleaned.estimatedBytes,
            freedBytes: cleaned.freedBytes,
            notes: notes
        )
    }

    /// The one folder a log entry names: the target, or the folder all targets are in, else the first target.
    static func folder(of paths: [String]) -> String {
        guard let first = paths.first else { return "" }
        guard paths.count > 1 else { return first }
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        return parents.count == 1 ? parents.first ?? first : first
    }
}
