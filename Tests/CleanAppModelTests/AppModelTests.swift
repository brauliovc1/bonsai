import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("App model")
@MainActor
struct AppModelTests {
    /// The app and `bonsai scan --json` must give every worktree the same verdict (one verdict for
    /// both: they share `WorktreeAssessor`). Both use the git the environment resolves.
    @Test func everyRowMatchesTheCLIVerdict() async throws {
        let world = try await DemoWorld.build()
        defer { world.remove() }
        let app = makeApp(world.fixture, isolatedGit: false)
        await app.refresh()
        let rows = WorktreesModel(app: app).allRows
        #expect(rows.count == world.items.count + world.repos.count)

        let environment = world.fixture.environment()
        let result = try await CLIBinary.run(
            ["scan", "--json", "--root", world.folder.path],
            environment: [
                "BONSAI_SETTINGS_DIR": environment.settingsDirectory.path,
                "CLAUDE_CONFIG_DIR": environment.claudeConfigDirectory.path,
            ]
        )
        #expect(result.succeeded, "\(result.stderr)")
        struct Output: Decodable {
            struct Verdict: Decodable {
                var path: String
                var status: String
            }
            var verdicts: [Verdict]
        }
        let output = try JSONDecoder().decode(Output.self, from: result.stdout)
        let cli = Dictionary(output.verdicts.map { ($0.path, $0.status) }) { first, _ in first }
        #expect(cli.count == rows.count)
        for row in rows {
            #expect(cli[row.path] == row.statusLabel, "\(row.path)")
        }
        for item in world.items {
            let row = try #require(rows.first { CanonicalPath.same($0.url, item.url) })
            #expect(item.mismatch(row.assessment) == nil, "\(world.relativePath(item.url))")
        }
    }

    @Test func refreshDuringAScanRunsExactlyOneMoreScan() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        try await fixture.addSiblingWorktree(to: repo, name: "task")
        let app = makeApp(fixture, root: fixture.scanRoot)

        app.requestRefresh()
        #expect(app.isScanning)
        // Wait until the first scan is really under way, then ask again and again.
        let deadline = ContinuousClock.now + TestWait.limit
        while app.progress == nil, app.isScanning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(app.isScanning, "the first scan finished before it could be interrupted")
        app.requestRefresh()
        app.requestRefresh()
        await app.refresh()
        #expect(app.scanCount == 2)
        #expect(!app.isScanning)
        #expect(app.progress == nil)

        await app.refresh()
        #expect(app.scanCount == 3, "a refresh when idle runs one scan")
        #expect(app.assessments.count == 2)
        #expect(app.problem == nil)
        #expect(app.lastScanAt != nil)
    }

    @Test func unreadableSettingsStopTheScan() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try await fixture.makeRepo("solo")
        let app = makeApp(fixture, root: fixture.scanRoot)
        try fixture.write("{ not json", to: SettingsStore.fileName, in: app.environment.settingsDirectory)

        await app.refresh()
        #expect(app.problem?.contains(SettingsStore.fileName) == true)
        #expect(app.assessments.isEmpty)
        #expect(app.scan == nil)
    }

    @Test func reclaimableCountsSafeAndAutoReady() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let expected = model.allRows
            .filter { $0.tone == .safe || $0.tone == .autoReady }
            .compactMap(\.sizeBytes)
            .reduce(0, +)
        #expect(app.reclaimableBytes == expected)
        #expect(app.reclaimableBytes > 20 * 1024 * 1024, "includes cobalt-web's node_modules")
    }

    @Test func diskSpaceOfTheTempVolume() {
        let disk = DiskSpaceModel(folder: FileManager.default.temporaryDirectory)
        let free = disk.freeBytes ?? 0
        let total = disk.totalBytes ?? 0
        #expect(free > 0)
        #expect(total > 0)
        #expect(total >= free)
        #expect(disk.volumeName?.isEmpty == false)
        #expect((0...1).contains(disk.usedFraction ?? -1))

        // A folder that doesn't exist (a scan root that was deleted) measures its nearest existing parent.
        disk.point(at: FileManager.default.temporaryDirectory.appending(path: "no-such-folder-\(UUID())/deeper"))
        #expect((disk.freeBytes ?? 0) > 0)
        #expect(disk.totalBytes == total)
    }
}
