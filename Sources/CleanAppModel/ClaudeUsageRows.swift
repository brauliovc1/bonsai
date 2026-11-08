import CleanCore
import Foundation

/// One transcript folder of `<claude config>/projects`, as the Claude usage screen shows it.
public struct ClaudeTranscriptRow: Identifiable, Hashable, Sendable {
    public let project: ClaudeUsageReport.TranscriptProject

    public init(project: ClaudeUsageReport.TranscriptProject) {
        self.project = project
    }

    public var id: String { project.folderName }
    /// The working folder when a known repo or worktree encodes to this name, else the raw folder name.
    public var title: String { project.decodedPath ?? project.folderName }
    public var isDecoded: Bool { project.decodedPath != nil }
    /// The working folder is known and no longer on disk: the "folder gone" badge.
    public var folderGone: Bool { project.folderIsGone }
    public var bytes: Int64 { project.bytes }
    public var sizeText: String { DisplayText.bytes(bytes) }
    /// Under the title: why the title is the raw name, when it is.
    public var note: String? { isDecoded ? nil : "path not recognized" }
}

/// A name and a size: a desktop-app child, or one line of the totals.
public struct ClaudeSizeLine: Identifiable, Hashable, Sendable {
    public let title: String
    public let detail: String?
    public let bytes: Int64

    public var id: String { title }
    public var sizeText: String { DisplayText.bytes(bytes) }
}
