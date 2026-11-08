@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Settings model")
@MainActor
struct SettingsModelTests {
    /// The folder a scan root may be: inside the fixture's home.
    static func code(_ fixture: GitFixture) -> URL {
        fixture.home.appending(path: "code", directoryHint: .isDirectory)
    }

    /// A fixture with one repo in `<home>/code`, an app model that reads its roots from settings (no
    /// environment override), and the settings model.
    private func makeWorld() async throws -> (GitFixture, AppModel, SettingsModel) {
        let fixture = try GitFixture()
        try await fixture.makeRepo("solo", in: Self.code(fixture))
        let app = AppModel(environment: fixture.environment(), git: fixture.git)
        return (fixture, app, SettingsModel(app: app))
    }

    private func saved(_ app: AppModel) throws -> Settings {
        try SettingsStore(environment: app.environment).load()
    }

    @Test func defaultsWhenThereIsNoFile() async throws {
        let (fixture, _, model) = try await makeWorld()
        defer { fixture.remove() }
        #expect(model.scanRoots.isEmpty)
        #expect(model.idleThresholdDays == 30)
        #expect(model.lowSpaceWarningGB == 10)
        #expect(model.error == nil)
        #expect(SettingsModel.emptyRootsText == "No folders added: ~/Documents/GitHub is scanned.")
        #expect(SettingsModel.idleThresholdRange == 7...365)
    }

    @Test func addingAndRemovingRootsIsSavedAndScansAgain() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let scans = app.scanCount

        let code = Self.code(fixture)
        #expect(await model.addRoot(code))
        #expect(model.scanRoots == [CanonicalPath.resolve(code)], "saved canonical")
        #expect(try saved(app).scanRoots == model.scanRoots, "persisted")
        #expect(app.scanCount == scans + 1, "changing the roots scanned again")
        #expect(app.roots.map(\.path) == model.scanRoots)
        #expect(app.assessments.count == 1, "the new root's repo was found")

        // A folder already in the list is not added twice, and doesn't scan again.
        #expect(await model.addRoot(code) == false)
        #expect(model.scanRoots.count == 1)
        #expect(app.scanCount == scans + 1)

        await model.removeRoot(model.scanRoots[0])
        #expect(model.scanRoots.isEmpty)
        #expect(try saved(app).scanRoots.isEmpty)
        #expect(app.scanCount == scans + 2)
        #expect(app.assessments.isEmpty, "an empty list scans ~/Documents/GitHub, which the fake home doesn't have")
        #expect(FileManager.default.fileExists(atPath: code.path), "removing a root leaves the folder alone")
    }

    @Test func onlyFoldersCanBeAdded() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let file = try fixture.write("x\n", to: "notes.txt", in: fixture.url)

        #expect(await model.addRoot(file) == false)
        #expect(model.error?.contains("not a folder") == true)
        #expect(await model.addRoot(fixture.url.appending(path: "no-such-folder")) == false)
        #expect(model.scanRoots.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: SettingsStore(environment: app.environment).fileURL.path),
                "nothing was saved")
    }

    @Test func theIdleThresholdIsClampedSavedAndScansAgain() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let scans = app.scanCount

        await model.setIdleThreshold(3)
        #expect(model.idleThresholdDays == 7, "7 is the lowest")
        #expect(try saved(app).idleThresholdDays == 7)
        await model.setIdleThreshold(1000)
        #expect(model.idleThresholdDays == 365, "365 is the highest")
        #expect(try saved(app).idleThresholdDays == 365)
        await model.setIdleThreshold(60)
        #expect(model.idleThresholdDays == 60)
        #expect(try saved(app).idleThresholdDays == 60)
        #expect(app.scanCount == scans + 3)
        #expect(app.settings.idleThresholdDays == 60)

        await model.setIdleThreshold(60)
        #expect(app.scanCount == scans + 3, "the same value changes nothing")
    }

    @Test func theThresholdSetsTheStatusesAfterTheRescan() async throws {
        let demo = try await DemoWorld.build()
        defer { demo.remove() }
        // The demo's folders sit next to the fixture's home; a scan root must be inside home.
        var environment = demo.fixture.environment(scanRoots: nil)
        environment.homeDirectory = demo.folder
        let app = AppModel(environment: environment, git: demo.fixture.git)
        let model = SettingsModel(app: app)
        #expect(await model.addRoot(demo.folder.appending(path: "root")))
        let archive = demo.folder.appending(path: "root/atlas-archive")
        func status() -> String? {
            app.assessments.first { CanonicalPath.same($0.worktree.url, archive) }?.status.label
        }
        #expect(status() == "AUTO-READY", "45 days idle, threshold 30")

        await model.setIdleThreshold(60)
        #expect(status() == "SAFE", "45 days idle is below a 60-day threshold")
        await model.setIdleThreshold(30)
        #expect(status() == "AUTO-READY")
    }

    @Test func theLowSpaceWarningIsClampedAndSavedWithoutAScan() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let scans = app.scanCount

        model.setLowSpaceWarning(25)
        #expect(model.lowSpaceWarningGB == 25)
        #expect(try saved(app).lowSpaceWarningGB == 25)
        #expect(app.settings.lowSpaceWarningGB == 25)
        model.setLowSpaceWarning(0)
        #expect(model.lowSpaceWarningGB == 1)
        model.setLowSpaceWarning(5000)
        #expect(model.lowSpaceWarningGB == 1000)
        #expect(app.scanCount == scans)
    }

    @Test func keysOwnedByOtherScreensAndTheCLIAreKept() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        var other = Settings()
        other.autoEnabled = true
        other.reportOnlyDays = 3
        other.includeClaudeInAuto = true
        try SettingsStore(environment: app.environment).save(other)

        await model.setIdleThreshold(90)

        let after = try saved(app)
        #expect(after.idleThresholdDays == 90)
        #expect(after.autoEnabled && after.reportOnlyDays == 3 && after.includeClaudeInAuto)
    }

    @Test func aBrokenSettingsFileIsNeverOverwritten() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let store = SettingsStore(environment: app.environment)
        try fixture.write("{ not json", to: SettingsStore.fileName, in: store.directory)

        model.load()
        #expect(model.error?.contains(SettingsStore.fileName) == true)
        await model.setIdleThreshold(45)
        model.setLowSpaceWarning(20)
        #expect(await model.addRoot(Self.code(fixture)) == false)

        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == "{ not json", "left exactly as it was")
        #expect(model.error != nil)
    }

    @Test func theEnvironmentOverrideIsExplained() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let withOverride = AppModel(environment: fixture.environment(scanRoots: [fixture.scanRoot]), git: fixture.git)
        #expect(SettingsModel(app: withOverride).overrideText?.contains("CLEAN_CLAUDE_SCAN_ROOTS") == true)
        let without = AppModel(environment: fixture.environment(), git: fixture.git)
        #expect(SettingsModel(app: without).overrideText == nil)
    }
}
