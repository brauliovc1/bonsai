@testable import CleanAppModel
@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@MainActor
struct QuickCleanTestWorld {
    let fixture: GitFixture
    let app: AppModel
    let quick: QuickCleanModel
    let tools: FakeToolchain
    let main: URL
    let old: URL
    let recent: URL
    let now: Date

    static func make(commands: Bool = false, unknown: Bool = false, processes: ProcessSource = ProcessSource { ProcessList(processes: []) }) async throws -> QuickCleanTestWorld {
        let fixture = try GitFixture()
        let now = Date(), tools = FakeToolchain()
        let aged = AgedRepos(fixture: fixture, now: now)
        let main = try await aged.repo("idle-eight", days: 8, gitignore: "node_modules/\n.claude/\n", files: ["source.txt": "source\n"])
        let old = fixture.scanRoot.appending(path: "old-worktree")
        try await aged.git(["worktree", "add", "--quiet", "-b", "old-branch", old.path], in: main, days: 8)
        let recent = try await aged.repo("recent", days: 2, gitignore: "node_modules/\n", files: ["source.txt": "recent\n"])
        for checkout in [main, old, recent] { try aged.blob(in: checkout, "node_modules/library/file", kibibytes: 8) }
        try await aged.age(main, days: 8); try await aged.age(old, days: 8); try await aged.age(recent, days: 2)
        var environment = fixture.environment(scanRoots: [fixture.scanRoot]).withFakeTools(docker: commands, xcrun: commands, developerTools: commands)
        environment.now = { now }
        try SettingsStore(environment: environment).save(Settings(scanRoots: [fixture.scanRoot.path], idleThresholdDays: 30))
        if unknown {
            let transcripts = environment.claudeConfigDirectory.appending(path: "projects/" + TranscriptFolderEncoding.encode(CanonicalPath.resolve(main)))
            try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: transcripts.path)
        }
        let app = AppModel(environment: environment, git: fixture.git)
        let worktrees = WorktreesModel(app: app), projects = ProjectsModel(app: app)
        let caches = CachesModel(app: app, processes: processes)
        let derived = DerivedDataModel(app: app, runner: tools.runner)
        let docker = DockerSimulatorsModel(app: app, runner: tools.runner)
        let trash = environment.homeDirectory.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let cleanupEnvironment = environment
        let downloads = DownloadsTrashModel(app: app, runner: tools.runner, trash: TrashOperation { source in
            #expect(try CleanupLock.tryAcquire(environment: cleanupEnvironment) == nil)
            let target = trash.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: target)
            return target
        }, dateAdded: { url in now.addingTimeInterval(url.lastPathComponent.hasPrefix("old") ? -31 * 86400 : -2 * 86400) })
        let quick = QuickCleanModel(app: app, worktrees: worktrees, projects: projects, caches: caches,
                                   derivedData: derived, dockerSimulators: docker, downloads: downloads)
        return QuickCleanTestWorld(fixture: fixture, app: app, quick: quick, tools: tools, main: main, old: old, recent: recent, now: now)
    }

    func group(_ kind: QuickCleanGroup.Kind) -> [QuickCleanItem] { quick.preview?.groups.first { $0.id == kind }?.items ?? [] }
    func matches(_ path: String?, _ url: URL) -> Bool { path.map { CanonicalPath.same(URL(fileURLWithPath: $0), url) } ?? false }
    func exists(_ path: URL) -> Bool { FileManager.default.fileExists(atPath: path.path) }
    func remove() {
        let path = app.environment.claudeConfigDirectory.appending(path: "projects")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: path.path)) ?? [] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.appending(path: name).path)
        }
        fixture.remove()
    }
}
