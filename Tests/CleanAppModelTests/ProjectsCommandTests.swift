import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("bonsai projects")
struct ProjectsCommandTests {
    private struct Output: Decodable {
        struct Total: Decodable, Equatable {
            var count: Int
            var bytes: Int64
        }

        struct Folder: Decodable {
            var path: String
            var relativePath: String
            var name: String
            var bytes: Int64?
        }

        struct Project: Decodable {
            var repo: String
            var path: String
            var kind: String
            var idleDays: Int?
            var status: String
            var totalBytes: Int64
            var folders: [Folder]
            var rebuild: [String]
        }

        struct Totals: Decodable {
            var idle: Total
            var all: Total
            var leftOut: Total
        }

        var idleDays: Int
        var filter: String
        var projects: [Project]
        var totals: Totals
        var problems: [String]
    }

    private func run(_ arguments: [String], fixture: GitFixture) async throws -> (Output, ProcessResult) {
        let environment = fixture.environment()
        let result = try await ProcessRunner.run(
            executable: try CLIBinary.url(),
            arguments: ["projects", "--json", "--root", fixture.scanRoot.path] + arguments,
            environmentAdditions: [
                "BONSAI_SETTINGS_DIR": environment.settingsDirectory.path,
                "CLAUDE_CONFIG_DIR": environment.claudeConfigDirectory.path,
            ],
            timeout: .seconds(120)
        )
        #expect(result.succeeded, "\(result.stderr)")
        return (try JSONDecoder().decode(Output.self, from: result.stdout), result)
    }

    @Test func jsonListsIdleProjectsBiggestFirstWithTotals() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try await ProjectFoldersDemo.add(to: fixture)
        let aged = AgedRepos(fixture: fixture)
        let golf = try await aged.repo("golf", days: 3, gitignore: ProjectFoldersDemo.gitignore)
        try aged.blob(in: golf, "node_modules/a.bin", kibibytes: 64)
        try await aged.age(golf, days: 3)

        let (idle, _) = try await run([], fixture: fixture)

        #expect(idle.filter == "idle")
        #expect(idle.idleDays == 30)
        #expect(idle.projects.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["delta", "echo", "foxtrot"])
        #expect(idle.projects.map(\.totalBytes) == idle.projects.map(\.totalBytes).sorted(by: >))
        for project in idle.projects {
            #expect(project.kind == "main")
            #expect(project.status == "Ready")
            #expect(project.totalBytes == project.folders.compactMap(\.bytes).reduce(0, +))
            #expect(project.folders.allSatisfy { $0.path == project.path + "/" + $0.relativePath })
        }
        let delta = try #require(idle.projects.first)
        #expect(delta.idleDays == 60)
        #expect(delta.folders.map(\.relativePath) == [".next", "node_modules"])
        #expect(delta.rebuild == ["npm install", ".next comes back with next build or next dev"])
        let idleBytes = idle.projects.reduce(0) { $0 + $1.totalBytes }
        #expect(idle.totals.idle == .init(count: 3, bytes: idleBytes))
        #expect(idle.totals.all.count == 4)
        #expect(idle.totals.leftOut.count == 1, "quiet-heron, the Claude worktree inside delta")
        #expect(idle.totals.leftOut.bytes >= 1024 * 1024)
        #expect(idle.problems.isEmpty)

        let (all, _) = try await run(["--all"], fixture: fixture)
        #expect(all.filter == "all")
        #expect(all.projects.count == 4)
        let recent = try #require(all.projects.first { $0.path.hasSuffix("/golf") })
        #expect(recent.status == "Recent" && recent.idleDays == 3)
        #expect(all.totals.all == idle.totals.all)

        let (strict, _) = try await run(["--idle-days", "50"], fixture: fixture)
        #expect(strict.projects.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["delta", "foxtrot"])
        #expect(strict.totals.idle.count == 2)

        // Read-only: nothing deleted, nothing written to the settings folder.
        #expect(FileManager.default.fileExists(atPath: fixture.scanRoot.appending(path: "delta/node_modules").path))
        let settings = fixture.environment().settingsDirectory
        let written = (try? FileManager.default.contentsOfDirectory(atPath: settings.path)) ?? []
        #expect(written.isEmpty, "\(written)")
    }
}
