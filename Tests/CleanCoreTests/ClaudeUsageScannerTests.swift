@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("ClaudeUsageScanner")
struct ClaudeUsageScannerTests {
    private func scanResult(repos: [URL] = [], worktrees: [URL] = [], roots: [URL] = []) -> ScanResult {
        ScanResult(
            roots: roots.map(\.path),
            repos: repos.map(\.path),
            worktrees: worktrees.map { url in
                Worktree(path: url.path, repoPath: repos.first?.path ?? url.path, head: nil, branch: nil, isMain: repos.contains(url), kind: .other)
            },
            sizes: [:],
            issues: [],
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 0
        )
    }

    @Test func transcriptTotalsAndTheFifteenLargestInOrder() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        // 17 project folders, 4 KiB * n each; the sizes are all different.
        for n in 1...17 {
            try home.addFile(".claude/projects/-raw-project-\(String(format: "%02d", n))/t.jsonl", kibibytes: 4 * n)
        }
        try home.addFile(".claude/projects/.DS_Store", kibibytes: 4)

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report.transcripts.projectCount == 17)
        #expect(report.transcripts.totalBytes == 4 * (17 * 18 / 2) * 1024)
        let largest = report.transcripts.largest
        #expect(largest.count == 15)
        #expect(largest.first?.folderName == "-raw-project-17")
        #expect(largest.first?.bytes == Int64(4 * 17 * 1024))
        #expect(largest.last?.folderName == "-raw-project-03")
        #expect(largest.map(\.bytes) == largest.map(\.bytes).sorted(by: >))
        #expect(!largest.contains { $0.folderName == "-raw-project-01" || $0.folderName == "-raw-project-02" })
        #expect(largest.allSatisfy { $0.decodedPath == nil && $0.decodedPathExists == nil && !$0.folderIsGone })
        #expect(report.warnings.isEmpty, "\(report.warnings)")
    }

    @Test func equalSizesAreOrderedByNameSoTheListIsStable() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        for name in ["-b", "-a", "-c"] {
            try home.addFile(".claude/projects/\(name)/t.jsonl", kibibytes: 8)
        }

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report.transcripts.largest.map(\.folderName) == ["-a", "-b", "-c"])
    }

    @Test func decodesFolderNamesOnlyWhenACandidatePathEncodesToExactlyThatName() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let root = try home.addFolder("Documents/GitHub")
        let repo = try home.addFolder("Documents/GitHub/app")
        let goneWorktree = home.url.appending(path: "Documents/GitHub/app-old")  // registered, folder deleted

        func projectFolder(_ path: URL) -> String { ClaudeProjectFolderName.encode(path.path) }
        try home.addFile(".claude/projects/\(projectFolder(repo))/a.jsonl", kibibytes: 16)
        try home.addFile(".claude/projects/\(projectFolder(goneWorktree))/a.jsonl", kibibytes: 12)
        try home.addFile(".claude/projects/\(projectFolder(root))/a.jsonl", kibibytes: 8)
        try home.addFile(".claude/projects/-Users-nobody-unknown-place/a.jsonl", kibibytes: 4)
        // Same characters as the repo's path but not equal to it: a prefix must not match.
        try home.addFile(".claude/projects/\(projectFolder(repo))-extra/a.jsonl", kibibytes: 20)

        let scan = scanResult(repos: [repo], worktrees: [repo, goneWorktree], roots: [root])
        let report = await ClaudeUsageScanner(environment: home.environment()).scan(using: scan)

        let projects = Dictionary(uniqueKeysWithValues: report.transcripts.largest.map { ($0.folderName, $0) })
        #expect(projects.count == 5)

        let repoProject = try #require(projects[projectFolder(repo)])
        #expect(repoProject.decodedPath == repo.path)
        #expect(repoProject.decodedPathExists == true)
        #expect(!repoProject.folderIsGone)

        let goneProject = try #require(projects[projectFolder(goneWorktree)])
        #expect(goneProject.decodedPath == goneWorktree.path)
        #expect(goneProject.decodedPathExists == false)
        #expect(goneProject.folderIsGone)

        let rootProject = try #require(projects[projectFolder(root)])
        #expect(rootProject.decodedPath == root.path)
        #expect(rootProject.decodedPathExists == true)

        let unknown = try #require(projects["-Users-nobody-unknown-place"])
        #expect(unknown.decodedPath == nil && unknown.decodedPathExists == nil && !unknown.folderIsGone)

        let extra = try #require(projects[projectFolder(repo) + "-extra"])
        #expect(extra.decodedPath == nil)
    }

    @Test func withoutAScanResultEveryFolderKeepsItsRawName() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let repo = try home.addFolder("Documents/GitHub/app")
        try home.addFile(".claude/projects/\(ClaudeProjectFolderName.encode(repo.path))/a.jsonl", kibibytes: 4)

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report.transcripts.largest.map(\.decodedPath) == [nil])
    }

    @Test func totalsFileHistoryVersionsAndDesktopData() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile(".claude/file-history/s1/a", kibibytes: 8)
        try home.addFile(".claude/file-history/s2/b", kibibytes: 4)

        // Versions: files and folders, a hidden file that is not a version, and a numeric sort check.
        try home.addFile(".local/share/claude/versions/2.1.10", kibibytes: 12)
        try home.addFile(".local/share/claude/versions/2.1.9", kibibytes: 8)
        try home.addFile(".local/share/claude/versions/2.1.25/claude", kibibytes: 16)
        try home.addFile(".local/share/claude/versions/.DS_Store", kibibytes: 4)

        // Desktop data: seven children (one hidden), the five biggest are listed.
        let desktop = "Library/Application Support/Claude"
        try home.addFile("\(desktop)/vm_bundles/rootfs.img", kibibytes: 96)
        try home.addFile("\(desktop)/Cache/c", kibibytes: 40)
        try home.addFile("\(desktop)/IndexedDB/i", kibibytes: 24)
        try home.addFile("\(desktop)/claude_desktop_config.json", kibibytes: 4)
        try home.addFile("\(desktop)/Local Storage/l", kibibytes: 16)
        try home.addFile("\(desktop)/Logs/l", kibibytes: 8)
        try home.addFile("\(desktop)/.hidden/h", kibibytes: 12)

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report.fileHistoryBytes == 12 * 1024)

        #expect(report.versions.count == 3)
        #expect(report.versions.names == ["2.1.9", "2.1.10", "2.1.25"])
        #expect(report.versions.totalBytes == 36 * 1024)

        #expect(report.desktop.totalBytes == (96 + 40 + 24 + 4 + 16 + 8 + 12) * 1024)
        let expectedLargest: [ClaudeUsageReport.SizedName] = [
            ClaudeUsageReport.SizedName(name: "vm_bundles", bytes: 96 * 1024),
            ClaudeUsageReport.SizedName(name: "Cache", bytes: 40 * 1024),
            ClaudeUsageReport.SizedName(name: "IndexedDB", bytes: 24 * 1024),
            ClaudeUsageReport.SizedName(name: "Local Storage", bytes: 16 * 1024),
            ClaudeUsageReport.SizedName(name: ".hidden", bytes: 12 * 1024),
        ]
        #expect(report.desktop.largestChildren == expectedLargest)

        #expect(report.warnings.isEmpty, "\(report.warnings)")
        #expect(report.totalBytes == report.transcripts.totalBytes + 12 * 1024 + 36 * 1024 + 200 * 1024)
    }

    /// Every file and folder under `root` with its size and modification date.
    private func snapshot(of root: URL) -> [String: String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return [:]
        }
        var entries: [String: String] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            entries[url.path] = "\(values?.isDirectory == true ? "d" : "f") \(values?.fileSize ?? -1) \(stamp)"
        }
        return entries
    }

    @Test func scanningLeavesEveryFileAndFolderUntouched() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let repo = try home.addFolder("Documents/GitHub/app")
        try home.addFile(".claude/projects/\(ClaudeProjectFolderName.encode(repo.path))/t.jsonl", kibibytes: 16)
        try home.addFile(".claude/projects/-other/t.jsonl", kibibytes: 8)
        try home.addFile(".claude/file-history/s1/a", kibibytes: 4)
        try home.addFile(".local/share/claude/versions/2.1.9", kibibytes: 8)
        try home.addFile("Library/Application Support/Claude/vm_bundles/img", kibibytes: 32)
        let before = snapshot(of: home.url)
        try #require(before.count > 10)

        let scan = scanResult(repos: [repo], worktrees: [repo], roots: [repo.deletingLastPathComponent()])
        let report = await ClaudeUsageScanner(environment: home.environment()).scan(using: scan)

        #expect(report.transcripts.projectCount == 2, "the scan really ran")
        #expect(snapshot(of: home.url) == before)
    }

    @Test func aSymlinkedProjectFolderIsMeasuredAsItsTarget() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let target = try home.addFolder("elsewhere/-linked")
        try home.addFile("elsewhere/-linked/t.jsonl", kibibytes: 40)
        try home.addFile(".claude/projects/-plain/t.jsonl", kibibytes: 8)
        try FileManager.default.createSymbolicLink(
            at: home.url.appending(path: ".claude/projects/-linked"),
            withDestinationURL: target
        )

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report.transcripts.largest.map(\.folderName) == ["-linked", "-plain"])
        #expect(report.transcripts.largest.first?.bytes == Int64(40 * 1024), "du alone reports a symlink as 0")
        #expect(report.transcripts.totalBytes == Int64(48 * 1024))
    }

    @Test func missingFoldersAreZerosNotErrors() async throws {
        let home = try FakeHome()
        defer { home.remove() }

        let report = await ClaudeUsageScanner(environment: home.environment()).scan()

        #expect(report == ClaudeUsageReport())
        #expect(report.warnings.isEmpty)
    }

    @Test func honorsAClaudeConfigDirectoryOutsideHome() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let elsewhere = try TemporaryDirectory(prefix: "clean-claude-config")
        defer { elsewhere.remove() }
        let project = elsewhere.url.appending(path: "projects/-p", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(count: 8192).write(to: project.appending(path: "t.jsonl"))
        try home.addFile(".claude/projects/-ignored/t.jsonl", kibibytes: 64)

        var environment = home.environment()
        environment.claudeConfigDirectory = elsewhere.url
        let report = await ClaudeUsageScanner(environment: environment).scan()

        #expect(report.transcripts.largest.map(\.folderName) == ["-p"])
        #expect(report.transcripts.totalBytes == 8192)
    }

    @Test func withoutDuTheReportIsEmptyWithAWarning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile(".claude/projects/-p/t.jsonl", kibibytes: 4)

        let report = await ClaudeUsageScanner(environment: home.environment(du: nil)).scan()

        #expect(report.transcripts.totalBytes == 0)
        #expect(report.warnings.count == 1)
    }

    @Test func reportSurvivesAJSONRoundTrip() throws {
        let report = ClaudeUsageReport(
            transcripts: .init(
                totalBytes: 9,
                projectCount: 2,
                largest: [.init(folderName: "-a", decodedPath: "/a", decodedPathExists: false, bytes: 5)]
            ),
            fileHistoryBytes: 3,
            versions: .init(count: 1, totalBytes: 4, names: ["2.1.9"]),
            desktop: .init(totalBytes: 7, largestChildren: [.init(name: "vm_bundles", bytes: 6)]),
            warnings: ["w"]
        )
        let data = try CleanJSON.encoder().encode(report)
        #expect(try CleanJSON.decoder().decode(ClaudeUsageReport.self, from: data) == report)
    }
}
