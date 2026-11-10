import Foundation

/// Where Claude's own data takes disk space. Read-only: Bonsai only measures these folders and
/// points to Claude's own Settings > This computer > Storage.
public struct ClaudeUsageReport: Sendable, Codable, Equatable {
    /// A file or folder and its allocated size.
    public struct SizedName: Sendable, Codable, Hashable {
        public var name: String
        public var bytes: Int64

        public init(name: String, bytes: Int64) {
            self.name = name
            self.bytes = bytes
        }
    }

    /// One folder of `<claude config>/projects`, which Claude names after the working folder's path.
    public struct TranscriptProject: Sendable, Codable, Hashable {
        /// The folder's name, e.g. `-Users-me-Documents-GitHub-app`.
        public var folderName: String
        /// The working folder the name stands for, when a known repo, worktree or scan root encodes to
        /// exactly this name. nil: the raw name is all there is.
        public var decodedPath: String?
        /// Whether `decodedPath` still exists; nil when there is no decoded path.
        public var decodedPathExists: Bool?
        public var bytes: Int64

        public init(folderName: String, decodedPath: String?, decodedPathExists: Bool?, bytes: Int64) {
            self.folderName = folderName
            self.decodedPath = decodedPath
            self.decodedPathExists = decodedPathExists
            self.bytes = bytes
        }

        /// The working folder is known and no longer on disk.
        public var folderIsGone: Bool { decodedPathExists == false }
    }

    public struct Transcripts: Sendable, Codable, Equatable {
        public var totalBytes: Int64
        public var projectCount: Int
        /// The biggest project folders, largest first.
        public var largest: [TranscriptProject]

        public init(totalBytes: Int64 = 0, projectCount: Int = 0, largest: [TranscriptProject] = []) {
            self.totalBytes = totalBytes
            self.projectCount = projectCount
            self.largest = largest
        }
    }

    /// `<home>/.local/share/claude/versions`: one entry per installed Claude Code version.
    public struct Versions: Sendable, Codable, Equatable {
        public var count: Int
        public var totalBytes: Int64
        /// Oldest first, compared as version numbers (`2.1.9` before `2.1.10`).
        public var names: [String]

        public init(count: Int = 0, totalBytes: Int64 = 0, names: [String] = []) {
            self.count = count
            self.totalBytes = totalBytes
            self.names = names
        }
    }

    /// The Claude desktop app's folder (`~/Library/Application Support/Claude`).
    public struct DesktopData: Sendable, Codable, Equatable {
        public var totalBytes: Int64
        /// The biggest children by name, largest first.
        public var largestChildren: [SizedName]

        public init(totalBytes: Int64 = 0, largestChildren: [SizedName] = []) {
            self.totalBytes = totalBytes
            self.largestChildren = largestChildren
        }
    }

    public var transcripts: Transcripts
    /// `<claude config>/file-history`.
    public var fileHistoryBytes: Int64
    public var versions: Versions
    public var desktop: DesktopData
    /// Things that went wrong without stopping the scan (an unreadable folder, a failed `du`).
    public var warnings: [String]

    public init(
        transcripts: Transcripts = Transcripts(),
        fileHistoryBytes: Int64 = 0,
        versions: Versions = Versions(),
        desktop: DesktopData = DesktopData(),
        warnings: [String] = []
    ) {
        self.transcripts = transcripts
        self.fileHistoryBytes = fileHistoryBytes
        self.versions = versions
        self.desktop = desktop
        self.warnings = warnings
    }

    public var totalBytes: Int64 {
        transcripts.totalBytes + fileHistoryBytes + versions.totalBytes + desktop.totalBytes
    }
}
