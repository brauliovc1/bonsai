@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation

/// `ProjectFoldersDemo` (delta 60 days, echo 45, foxtrot 90, the Claude worktree quiet-heron inside delta) plus
/// `golf`, worked on 3 days ago, and with `unknownIdle` `hotel`, 50 days old but with a Claude transcript folder
/// that can't be read (idle unknown). Every project has an ignored `node_modules` at least. Scanned once.
@MainActor
struct ProjectsWorld {
    let fixture: GitFixture
    let models: ScreenModels
    var app: AppModel { models.app }
    var projects: ProjectsModel { models.projects }
    var environment: CleanEnvironment { app.environment }

    static func make(unknownIdle: Bool = false, gate: ProcessGate? = nil, scanProjects: Bool = true) async throws -> ProjectsWorld {
        let fixture = try GitFixture()
        let now = Date()
        try await ProjectFoldersDemo.add(to: fixture, now: now)
        let aged = AgedRepos(fixture: fixture, now: now)
        let golf = try await aged.repo("golf", days: 3, gitignore: ProjectFoldersDemo.gitignore, files: ["yarn.lock": "\n"])
        try aged.blob(in: golf, "node_modules/a/index.bin", kibibytes: 128)
        try await aged.age(golf, days: 3)
        var environment = fixture.environment(scanRoots: [fixture.scanRoot]).withFakeTools()
        if unknownIdle {
            let hotel = try await aged.repo("hotel", days: 50, gitignore: ProjectFoldersDemo.gitignore)
            try aged.blob(in: hotel, "node_modules/a/index.bin", kibibytes: 64)
            try await aged.age(hotel, days: 50)
            let transcripts = environment.claudeConfigDirectory
                .appending(path: "projects/" + TranscriptFolderEncoding.encode(CanonicalPath.resolve(hotel)))
            try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: transcripts.path)
        }
        var git = fixture.git
        if let gate {
            try gate.install(in: fixture.url, realGit: git.executable)
            git.executable = gate.git
            environment.tools.lsof = gate.lsof
        }
        let app = AppModel(environment: environment, git: git)
        let world = ProjectsWorld(fixture: fixture, models: ScreenModels(app: app, runner: FakeToolchain().runner))
        await app.refresh()
        if scanProjects { await world.projects.refresh() }
        return world
    }

    func remove() {
        let transcripts = environment.claudeConfigDirectory.appending(path: "projects")
        if let folders = try? FileManager.default.contentsOfDirectory(atPath: transcripts.path) {
            for folder in folders {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: transcripts.appending(path: folder).path)
            }
        }
        fixture.remove()
    }

    func url(_ name: String) -> URL {
        if name == "quiet-heron" { return url("delta").appending(path: ".claude/worktrees/quiet-heron", directoryHint: .isDirectory) }
        return fixture.scanRoot.appending(path: name, directoryHint: .isDirectory)
    }

    func exists(_ relative: String, in name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).appending(path: relative).path)
    }

    func row(_ name: String) -> ProjectRow? {
        projects.allRows.first { CanonicalPath.same($0.url, url(name)) }
    }

    func ids(_ names: [String]) -> Set<ProjectRow.ID> {
        Set(names.compactMap { row($0)?.id })
    }

    func logEntries() throws -> [RemovalLogEntry] {
        try RemovalLog(environment: environment).entries()
    }
}
