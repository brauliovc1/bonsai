import CleanCore
import Foundation

/// What happened to one worktree's confirmed folders: each deleted, refused (with `LightCleaner`'s reason)
/// or failed, with the space measured around each delete.
public struct LightCleanOutcome: Identifiable, Sendable {
    public struct Folder: Identifiable, Sendable, Hashable {
        public enum Status: Sendable, Hashable {
            /// `freedBytes`: free space after minus before this delete; nil when the volume couldn't be read.
            case deleted(freedBytes: Int64?)
            case refused(String)
            case failed(String)
        }

        public let relativePath: String
        public let estimatedBytes: Int64?
        public let packageClones: [String]
        public let status: Status

        public var id: String { relativePath }
        public var isDeleted: Bool {
            if case .deleted = status { return true }
            return false
        }
    }

    public let item: LightCleanConfirmation.Item
    /// One per confirmed folder, in the order they were confirmed.
    public let folders: [Folder]
    /// Why nothing in the worktree was attempted (a process inside, no longer registered, another cleanup).
    public let error: String?
    /// Things that went wrong after deleting (a log entry not written).
    public let warnings: [String]
    /// Sum of the per-folder measurements; nil when nothing was deleted or a volume couldn't be read.
    public let freedBytes: Int64?

    public var id: WorktreeRow.ID { item.id }
    public var deletedCount: Int { folders.filter(\.isDeleted).count }

    /// Refused for the whole worktree before any folder was tried.
    init(item: LightCleanConfirmation.Item, error: String) {
        self.item = item
        self.error = error
        self.warnings = []
        self.freedBytes = nil
        self.folders = item.candidates.map {
            Folder(relativePath: $0.relativePath, estimatedBytes: $0.estimatedBytes, packageClones: $0.packageClones,
                   status: .refused(error))
        }
    }

    init(item: LightCleanConfirmation.Item, result: LightCleanResult) {
        self.item = item
        self.error = nil
        self.warnings = result.warnings
        self.freedBytes = result.freedBytes
        self.folders = item.candidates.map { candidate in
            let status: Folder.Status
            if result.deleted.contains(where: { $0.relativePath == candidate.relativePath }) {
                let entry = result.entries.first { $0.path == candidate.path }
                status = .deleted(freedBytes: entry?.freedBytes)
            } else if let failure = result.failed.first(where: { $0.candidate.relativePath == candidate.relativePath }) {
                status = .failed(failure.message)
            } else if let refusal = result.refused.first(where: { $0.relativePath == candidate.relativePath }) {
                status = .refused(CleanupPresentation.reason(refusal.reason))
            } else {
                status = .refused("it was not reached")
            }
            return Folder(relativePath: candidate.relativePath, estimatedBytes: candidate.estimatedBytes,
                          packageClones: candidate.packageClones, status: status)
        }
    }
}
