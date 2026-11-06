import Foundation

/// Measures Claude's transcripts, file history, Claude Code versions and desktop app data.
///
/// Read-only by design: this folder has no delete, trash or save API, and a test fails if one appears.
/// Totals are the sum of the folder's children measured with `du`, so each folder is read once.
public struct ClaudeUsageScanner: Sendable {
    public static let largestProjectCount = 15
    public static let largestDesktopChildCount = 5

    public var environment: CleanEnvironment

    public init(environment: CleanEnvironment) {
        self.environment = environment
    }

    private struct Child {
        var url: URL
        var bytes: Int64
        var name: String { url.lastPathComponent }
    }

    /// `scanResult` supplies the repos, worktrees and scan roots whose paths transcript folders are
    /// matched against; without it every transcript folder keeps its raw name.
    public func scan(using scanResult: ScanResult? = nil) async -> ClaudeUsageReport {
        guard let du = environment.tools.du else {
            return ClaudeUsageReport(warnings: ["/usr/bin/du not found; Claude data sizes skipped"])
        }
        let sizer = DirectorySizer(du: du)
        var warnings: [String] = []

        // Transcripts.
        let projectsDirectory = environment.claudeConfigDirectory.appending(path: "projects", directoryHint: .isDirectory)
        let projects = await measuredChildren(of: projectsDirectory, includeHidden: false, sizer: sizer, warnings: &warnings)
        let table = ClaudeProjectFolderName.decodingTable(candidates: Self.candidatePaths(from: scanResult))
        let largestProjects = Self.largestFirst(projects).prefix(Self.largestProjectCount).map { project in
            let decoded = table[project.name]
            return ClaudeUsageReport.TranscriptProject(
                folderName: project.name,
                decodedPath: decoded,
                decodedPathExists: decoded.map { FileManager.default.fileExists(atPath: $0) },
                bytes: project.bytes
            )
        }

        // File history.
        let fileHistory = environment.claudeConfigDirectory.appending(path: "file-history", directoryHint: .isDirectory)
        var fileHistoryBytes: Int64 = 0
        do {
            fileHistoryBytes = try await sizer.allocatedSize(ofItem: fileHistory) ?? 0
        } catch {
            warnings.append("\(fileHistory.path): \(error)")
        }

        // Claude Code versions.
        let versionsDirectory = environment.homeDirectory
            .appending(path: ".local/share/claude/versions", directoryHint: .isDirectory)
        let versionChildren = Self.children(of: versionsDirectory, includeHidden: false, warnings: &warnings)
        let versionSizes = await sizer.allocatedSizes(ofItems: versionChildren)
        warnings += versionSizes.issues.map(\.description)

        // Desktop app data.
        let desktop = await measuredChildren(
            of: environment.claudeDesktopDirectory,
            includeHidden: true,
            sizer: sizer,
            warnings: &warnings
        )

        return ClaudeUsageReport(
            transcripts: .init(
                totalBytes: projects.reduce(0) { $0 + $1.bytes },
                projectCount: projects.count,
                largest: Array(largestProjects)
            ),
            fileHistoryBytes: fileHistoryBytes,
            versions: .init(
                count: versionChildren.count,
                totalBytes: versionSizes.sizes.values.reduce(0, +),
                names: versionChildren.map(\.lastPathComponent)
                    .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            ),
            desktop: .init(
                totalBytes: desktop.reduce(0) { $0 + $1.bytes },
                largestChildren: Self.largestFirst(desktop).prefix(Self.largestDesktopChildCount)
                    .map { ClaudeUsageReport.SizedName(name: $0.name, bytes: $0.bytes) }
            ),
            warnings: warnings
        )
    }

    // MARK: Pieces

    /// The paths a transcript folder name can be matched to: scan roots, repos and worktrees, each also
    /// with symlinks resolved (`/tmp` and `/private/tmp`).
    static func candidatePaths(from scanResult: ScanResult?) -> [String] {
        guard let scanResult else { return [] }
        var paths = Set<String>()
        for path in scanResult.roots + scanResult.repos + scanResult.worktrees.map(\.path) {
            paths.insert(path)
            paths.insert(CanonicalPath.resolve(path))
        }
        return paths.sorted()
    }

    private func measuredChildren(
        of directory: URL,
        includeHidden: Bool,
        sizer: DirectorySizer,
        warnings: inout [String]
    ) async -> [Child] {
        let urls = Self.children(of: directory, includeHidden: includeHidden, warnings: &warnings)
        let measured = await sizer.allocatedSizes(ofItems: urls)
        warnings += measured.issues.map(\.description)
        return urls.compactMap { url in measured.sizes[url.path].map { Child(url: url, bytes: $0) } }
    }

    /// The entries of a folder, by name. A missing folder has none; an unreadable one adds a warning.
    /// `.DS_Store` is never an entry.
    private static func children(of directory: URL, includeHidden: Bool, warnings: inout [String]) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            return try FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: includeHidden ? [] : [.skipsHiddenFiles]
                )
                .filter { $0.lastPathComponent != ".DS_Store" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            warnings.append("\(directory.path): \(error.localizedDescription)")
            return []
        }
    }

    /// Largest first; equal sizes by name, so the order is the same on every run.
    private static func largestFirst(_ children: [Child]) -> [Child] {
        children.sorted { lhs, rhs in
            lhs.bytes != rhs.bytes ? lhs.bytes > rhs.bytes : lhs.name < rhs.name
        }
    }
}
