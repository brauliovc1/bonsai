import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@MainActor
struct DownloadsModelWorld {
    let fixture: GitFixture
    let app: AppModel
    var downloads: URL { app.environment.homeDirectory.appending(path: "Downloads") }
    var trash: URL { app.environment.homeDirectory.appending(path: ".Trash") }
    init() throws {
        fixture = try GitFixture()
        app = makeApp(fixture)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    func file(_ name: String) throws -> URL {
        let url = downloads.appending(path: name)
        try Data("fixture".utf8).write(to: url)
        return url
    }
    var runner: CommandRunner {
        CommandRunner { url, _, _ in
            let output = url.lastPathComponent == "hdiutil" ? "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>images</key><array/></dict></plist>"
                : url.lastPathComponent == "tmutil" ? "Snapshots for volume group containing disk /:\ncom.apple.TimeMachine.2026-10-01-100000.local\n" : "16\tfixture\n"
            return ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", timedOut: false)
        }
    }
    func model(emptier: any TrashEmptier = UnavailableTrashEmptier()) -> DownloadsTrashModel {
        let directory = trash
        let environment = app.environment
        let old = environment.now().addingTimeInterval(-31 * 86400)
        let operation = TrashOperation { source in
            #expect(try CleanupLock.tryAcquire(environment: environment) == nil)
            let destination = directory.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        return DownloadsTrashModel(app: app, runner: runner, trash: operation, emptier: emptier, dateAdded: { _ in old })
    }
}

@MainActor
final class ModelTrashEmptier: TrashEmptier {
    var calls = 0
    var denied = false
    func empty() async throws {
        calls += 1
        if denied { throw TrashEmptyError.automationDenied }
    }
}
