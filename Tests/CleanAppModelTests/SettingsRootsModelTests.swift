@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Wave 4: what Settings accepts as a scan root, and what it does with settings it didn't write.
@Suite("Settings model: scan roots and the threshold from the file")
@MainActor
struct SettingsRootsModelTests {
    private func makeWorld() async throws -> (GitFixture, AppModel, SettingsModel) {
        let fixture = try GitFixture()
        try await fixture.makeRepo("solo", in: SettingsModelTests.code(fixture))
        let app = AppModel(environment: fixture.environment(), git: fixture.git)
        return (fixture, app, SettingsModel(app: app))
    }

    private func settingsFile(_ app: AppModel) -> URL {
        SettingsStore(environment: app.environment).fileURL
    }

    @Test func theWholeDiskHomeAndSystemFoldersAreRefusedWithAMessage() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let scans = app.scanCount
        let link = fixture.home.appending(path: "link-to-opt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/opt"))

        let cases: [(URL, String)] = [
            (URL(fileURLWithPath: "/"), "whole disk"),
            (app.environment.homeDirectory, "home folder itself"),
            (app.environment.homeDirectory.deletingLastPathComponent(), "contains the home folder"),
            (URL(fileURLWithPath: "/opt"), "outside the home folder"),
            (URL(fileURLWithPath: "/usr"), "outside the home folder"),
            (URL(fileURLWithPath: "/Library"), "outside the home folder"),
            (URL(fileURLWithPath: "/Volumes"), "volume's root"),
            (link, "leads to"),
        ]
        for (folder, text) in cases {
            #expect(await model.addRoot(folder) == false, "\(folder.path)")
            let error = model.error ?? ""
            #expect(error.contains("can't be a scan root") && error.contains(text), "\(folder.path): \(error)")
        }

        #expect(model.scanRoots.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: settingsFile(app).path), "nothing was saved")
        #expect(app.scanCount == scans, "and nothing was scanned")
    }

    @Test func aSymlinkIsStoredAsItsTargetAndThenCountsAsAlreadyThere() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let code = SettingsModelTests.code(fixture)
        let alias = fixture.home.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: code)

        #expect(await model.addRoot(alias))
        #expect(model.scanRoots == [CanonicalPath.resolve(code)])
        #expect(try SettingsStore(environment: app.environment).load().scanRoots == model.scanRoots)
        #expect(await model.addRoot(code) == false, "the target is the same folder")
        #expect(await model.addRoot(alias) == false)
        #expect(model.scanRoots.count == 1)
        #expect(app.assessments.count == 1, "the repo behind the link was scanned")
    }

    @Test func aFileHoldingSuchRootsReportsThemSkipsThemAndLetsThemBeRemoved() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        let code = SettingsModelTests.code(fixture)
        var settings = Settings()
        settings.scanRoots = ["/", "/opt", code.path]
        try SettingsStore(environment: app.environment).save(settings)

        model.load()
        await app.refresh()

        #expect(model.scanRoots == ["/", "/opt", code.path], "the file is shown as it is")
        #expect(model.refusedRoots.map(\.path) == ["/", "/opt"])
        #expect(model.skippedReason(of: "/")?.contains("whole disk") == true)
        #expect(model.skippedReason(of: "/opt") != nil)
        #expect(model.skippedReason(of: code.path) == nil)
        #expect(app.roots.map(\.path) == [CanonicalPath.resolve(code)], "only the accepted root is scanned")
        let reported = app.issues.filter { $0.kind == .rootRefused }
        #expect(reported.map(\.path) == ["/", "/opt"], "\(app.issues)")
        #expect(app.assessments.count == 1)

        await model.removeRoot("/")
        await model.removeRoot("/opt")
        #expect(model.scanRoots == [code.path])
        #expect(model.refusedRoots.isEmpty)
        #expect(app.issues.filter { $0.kind == .rootRefused }.isEmpty)
    }

    @Test func aThresholdOutsideSevenToThreeSixtyFiveInTheFileIsASettingsError() async throws {
        let (fixture, app, model) = try await makeWorld()
        defer { fixture.remove() }
        for days in [1, 6, 366] {
            try fixture.write(#"{"idleThresholdDays": \#(days)}"#, to: SettingsStore.fileName, in: app.environment.settingsDirectory)

            await app.refresh()
            #expect(app.problem?.contains("idleThresholdDays must be 7 to 365") == true, "\(days): \(app.problem ?? "nil")")
            #expect(app.assessments.isEmpty && app.scan == nil, "nothing is judged with a threshold of \(days)")
            model.load()
            #expect(model.error?.contains("idleThresholdDays must be 7 to 365") == true)
            await model.setIdleThreshold(30)
            #expect(try String(contentsOf: settingsFile(app), encoding: .utf8) == #"{"idleThresholdDays": \#(days)}"#,
                    "a file with a bad value is left for the person to fix")
        }

        try fixture.write(#"{"idleThresholdDays": 7}"#, to: SettingsStore.fileName, in: app.environment.settingsDirectory)
        await app.refresh()
        #expect(app.problem == nil)
        #expect(app.settings.idleThresholdDays == 7)
    }
}
