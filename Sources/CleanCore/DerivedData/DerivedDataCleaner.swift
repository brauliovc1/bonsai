import Foundation

/// Deletes orphaned DerivedData folders (PLAN §4.4). It takes only `OrphanedDerivedData`, which only the
/// scanner makes, and only for orphaned entries.
///
/// Right before deleting each one it checks again that the root is an acceptable DerivedData root, that
/// the folder is still a real folder, and that its `info.plist` still names the same workspace, which still
/// does not exist (and is not on an unmounted volume). Each deleted folder gets its own `derivedDataDelete`
/// log entry, written right after its delete.
public struct DerivedDataCleaner: Sendable {
    public var log: RemovalLog
    /// For the root check: the home folder and the folders above it are never cleaned.
    public var homeDirectory: URL
    public var now: @Sendable () -> Date
    var classifier = DerivedDataClassifier()
    /// Test seam: the free space of the root's volume (default: read from the volume).
    var freeSpace: FreeSpaceProbe?
    /// Test seam: runs before an orphan's re-check.
    var beforeDelete: @Sendable (OrphanedDerivedData) async -> Void = { _ in }

    public init(log: RemovalLog, homeDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.log = log
        self.homeDirectory = homeDirectory
        self.now = now
    }

    public init(environment: CleanEnvironment) {
        self.init(log: RemovalLog(environment: environment), homeDirectory: environment.homeDirectory, now: environment.now)
    }

    public func delete(_ orphans: [OrphanedDerivedData]) async -> DerivedDataDeletion {
        var result = DerivedDataDeletion(deleted: [], refused: [], failed: [], entries: [], warnings: [], logged: true)
        var freed: [Int64?] = []
        for orphan in orphans.uniqued() {
            await beforeDelete(orphan)
            let probe = freeSpace ?? .volume(containing: URL(fileURLWithPath: orphan.root, isDirectory: true))
            let before = probe.availableBytes()
            if let reason = refusal(for: orphan) {
                result.refused.append(DerivedDataDeletion.Refusal(orphan: orphan, reason: reason))
                continue
            }
            var failure: String?
            do {
                try FileManager.default.removeItem(at: orphan.url)
            } catch {
                failure = error.localizedDescription
            }
            let after = probe.availableBytes()
            let bytes = before.flatMap { before in after.map { max(0, $0 - before) } }
            freed.append(bytes)
            if let failure {
                result.failed.append(DerivedDataDeletion.Failure(orphan: orphan, message: failure))
            } else {
                result.deleted.append(orphan)
            }
            record(entry(for: orphan, failure: failure, freedBytes: bytes), in: &result)
        }
        if !freed.isEmpty, freed.allSatisfy({ $0 != nil }) {
            result.freedBytes = freed.compactMap { $0 }.reduce(0, +)
        }
        return result
    }

    /// Why `orphan` must not be deleted now, or nil when it is still orphaned.
    func refusal(for orphan: OrphanedDerivedData) -> String? {
        if let refusal = DerivedDataRootCheck.refusal(root: URL(fileURLWithPath: orphan.root), home: homeDirectory) {
            return refusal
        }
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

    /// One entry per folder: `path` is the folder, `repoPath` the DerivedData root.
    private func entry(for orphan: OrphanedDerivedData, failure: String?, freedBytes: Int64?) -> RemovalLogEntry {
        let note = failure.map { "failed to delete \(orphan.name) (project \(orphan.workspacePath)): \($0)" }
            ?? "deleted \(orphan.name): project \(orphan.workspacePath)"
        return RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: .derivedDataDelete,
            repoPath: orphan.root,
            path: orphan.folder,
            estimatedBytes: orphan.bytes,
            freedBytes: freedBytes,
            notes: [note]
        )
    }

    private func record(_ entry: RemovalLogEntry, in result: inout DerivedDataDeletion) {
        result.entries.append(entry)
        do {
            try log.append(entry)
        } catch {
            result.logged = false
            result.warnings.append("\(entry.path) was not logged: \(error)")
        }
    }
}
