@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches: Overview row and CLI")
@MainActor
struct CachesOverviewAndCLITests {
    /// The Tool caches part of the total is what the ready entries hold; its card opens the screen with them
    /// selected.
    @Test func theOverviewCountsTheReadyEntries() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let models = ScreenModels(app: AppModel(environment: world.environment), runner: FakeToolchain().runner,
                                  processes: world.processes.source)
        #expect(models.overview.summary.state(.toolCaches) == .notMeasured)
        world.processes.run("npm install")
        await models.caches.refresh()

        let card = try #require(models.overview.card(.toolCaches))
        #expect(card.title == "Tool caches")
        #expect(card.detail == "14 caches the tools download again when needed")
        #expect(card.bytes == models.caches.readyBytes && card.bytes > 0)
        #expect(models.overview.summary.count(.toolCaches) == 14, "npm waits for its tool to quit: not counted")
        models.overview.open(.toolCaches)
        #expect(models.navigation.section == .caches)
        #expect(models.caches.selection == Set(models.caches.readyRows.map(\.id)))
        #expect(models.caches.selectedBytes == card.bytes)
        #expect(SidebarSection.caches.title == "Tool caches")
    }

    /// `caches --json` on a temp home: every entry with id, section, paths, size and verdict.
    @Test func cachesJSONHasEveryEntryWithItsVerdict() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let result = try await run(["caches", "--json", "--home", world.url.path], world: world)
        #expect(result.succeeded, "\(result.stderr)")

        struct Output: Decodable {
            struct Entry: Decodable {
                var id: String
                var name: String
                var section: String
                var paths: [String]
                var removals: [String]
                var never: [String]
                var bytes: Int64?
                var verdict: String
                var reason: String?
                var runningOwners: [String]
                var note: String
            }
            var entries: [Entry]
            var cursorRunning: Bool
            var readyCount: Int
            var readyBytes: Int64
            var warnings: [String]
        }
        let output = try JSONDecoder().decode(Output.self, from: result.stdout)
        #expect(output.entries.map(\.id) == ToolCacheCatalog.entries.map(\.id))
        #expect(Set(output.entries.map(\.section)) == ["packages", "cursor"])
        let state = try #require(output.entries.first { $0.id == "cursor-state" })
        #expect(state.verdict == "display-only" && state.reason == "Your chats and settings" && state.removals.isEmpty)
        let pip = try #require(output.entries.first { $0.id == "pip" })
        #expect(pip.paths == [world.path("Library/Caches/pip")])
        #expect(["ready", "refused"].contains(pip.verdict), "the real ps decides whether pip runs on this Mac")
        #expect((pip.bytes ?? 0) > 0)
        let versions = try #require(output.entries.first { $0.id == "cursor-agent-versions" })
        #expect(versions.never == [CursorAgentVersions.linkPath])
        #expect(output.readyCount == output.entries.filter { $0.verdict == "ready" }.count)
    }

    /// `caches clean npm` without --yes prints the plan and deletes nothing, writes no lock and no log.
    @Test func cleanWithoutYesChangesNothing() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let before = try FileManager.default.subpathsOfDirectory(atPath: world.url.path).sorted()
        let result = try await run(["caches", "clean", "npm", "cursor-agent-versions", "--home", world.url.path], world: world)
        #expect(result.succeeded, "\(result.stderr)")
        #expect(result.stdoutString.contains("Nothing was changed. Add --yes to clean them."))
        #expect(result.stdoutString.contains("npm: "))
        #expect(result.stdoutString.contains("cursor-agent-versions: "))
        #expect(try FileManager.default.subpathsOfDirectory(atPath: world.url.path).sorted() == before)

        let shownOnly = try await run(["caches", "clean", "cursor-state", "--home", world.url.path], world: world)
        #expect(!shownOnly.succeeded && shownOnly.stderr.contains("cursor-state is shown only; it is never cleaned"))
        let uv = try await run(["caches", "clean", "uv", "--home", world.url.path], world: world)
        #expect(!uv.succeeded && uv.stderr.contains("uv is not an entry"), "uv left the catalog")
        let outside = try await run(["caches", "--home", "/Users"], world: world)
        #expect(!outside.succeeded && outside.stderr.contains("--home is for tests"))
    }

    /// `--yes` while another cleanup holds cleanup.lock is refused before anything is looked at.
    @Test func cleanWithYesWaitsForTheCleanupLock() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let lock = try #require(try CleanupLock.tryAcquire(environment: world.environment))
        defer { lock.release() }
        let result = try await run(["caches", "clean", "go-build", "--yes", "--home", world.url.path], world: world)
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains(CleanupLock.busyMessage))
        #expect(world.exists("Library/Caches/go-build/trim.txt"))
        #expect(try RemovalLog(environment: world.environment).entries().isEmpty)
    }

    private func run(_ arguments: [String], world: ToolCacheWorld) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: try CLIBinary.url(),
            arguments: arguments,
            environmentAdditions: ["CLEAN_CLAUDE_SETTINGS_DIR": world.environment.settingsDirectory.path],
            timeout: .seconds(120)
        )
    }
}
