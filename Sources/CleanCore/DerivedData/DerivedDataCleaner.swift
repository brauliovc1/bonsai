import Foundation

/// Deletes orphaned DerivedData folders (PLAN §4.4). It takes only `OrphanedDerivedData`, which only the
/// scanner makes, and only for orphaned entries.
///
/// Right before deleting each one it checks again that the folder is still a real folder and that its
/// `info.plist` still names the same workspace, which still does not exist. One `derivedDataDelete` log
/// entry lists every folder with its project path.
public struct DerivedDataCleaner: Sendable {
    public var log: RemovalLog
    public var now: @Sendable () -> Date
    var classifier = DerivedDataClassifier()
    /// Test seam: the free space of the root's volume (default: read from the volume).
    var freeSpace: FreeSpaceProbe?

    public init(log: RemovalLog, now: @escaping @Sendable () -> Date = { Date() }) {
        self.log = log
        self.now = now
    }

    public init(environment: CleanEnvironment) {
        self.init(log: RemovalLog(environment: environment), now: environment.now)
    }

    public func delete(_ orphans: [OrphanedDerivedData]) async -> DerivedDataDeletion {
        var result = DerivedDataDeletion(deleted: [], refused: [], failed: [], entry: nil, warnings: [], logged: true)
        let queue = orphans.uniqued()
        guard let first = queue.first else { return result }
        let probe = freeSpace ?? .volume(containing: URL(fileURLWithPath: first.root, isDirectory: true))
        let before = probe.availableBytes()

        for orphan in queue {
            if let reason = refusal(for: orphan) {
                result.refused.append(DerivedDataDeletion.Refusal(orphan: orphan, reason: reason))
                continue
            }
            do {
                try FileManager.default.removeItem(at: orphan.url)
                result.deleted.append(orphan)
            } catch {
                result.failed.append(DerivedDataDeletion.Failure(orphan: orphan, message: error.localizedDescription))
            }
        }
        guard !result.deleted.isEmpty || !result.failed.isEmpty else { return result }

        let after = probe.availableBytes()
        let estimates = result.deleted.compactMap(\.bytes)
        let entry = RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: .derivedDataDelete,
            repoPath: first.root,
            path: first.root,
            estimatedBytes: estimates.isEmpty ? nil : estimates.reduce(0, +),
            freedBytes: before.flatMap { before in after.map { max(0, $0 - before) } },
            notes: Self.logNotes(result)
        )
        result.entry = entry
        do {
            try log.append(entry)
        } catch {
            result.logged = false
            result.warnings.append("the DerivedData delete was not logged: \(error)")
        }
        return result
    }

    /// Why `orphan` must not be deleted now, or nil when it is still orphaned.
    func refusal(for orphan: OrphanedDerivedData) -> String? {
        guard !orphan.name.isEmpty, !orphan.name.contains("/"), orphan.name != ".", orphan.name != ".." else {
            return "\(orphan.name) is not a folder name"
        }
        guard DirectoryEntries.kind(ofItemAt: orphan.folder) == .directory else {
            return "it is no longer a folder"
        }
        let current = classifier.classify(orphan.url)
        switch current.state {
        case .orphaned:
            guard current.workspacePath == orphan.workspacePath else {
                return "its info.plist now names \(current.workspacePath ?? "no project")"
            }
            return nil
        case .live:
            return "its project is back at \(current.workspacePath ?? orphan.workspacePath)"
        default:
            return "it is now \(current.state.label)" + (current.detail.map { " (\($0))" } ?? "")
        }
    }

    /// One line per folder: its name and project path, or why it was refused or failed.
    static func logNotes(_ result: DerivedDataDeletion) -> [String] {
        result.deleted.map { "deleted \($0.name): project \($0.workspacePath)" }
            + result.refused.map { "refused \($0.orphan.name): \($0.reason)" }
            + result.failed.map { "failed \($0.orphan.name) (project \($0.orphan.workspacePath)): \($0.message)" }
    }
}
