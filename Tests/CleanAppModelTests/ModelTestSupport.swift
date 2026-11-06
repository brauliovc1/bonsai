import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation

/// An `AppModel` that scans `root` (default: the whole fixture) with settings and log inside the
/// fixture's home. `isolatedGit`: the fixture's git, which ignores the user's git config; false uses the
/// git the environment resolves, as the app and the CLI do.
@MainActor
func makeApp(_ fixture: GitFixture, root: URL? = nil, isolatedGit: Bool = true) -> AppModel {
    AppModel(environment: fixture.environment(scanRoots: [root ?? fixture.url]), git: isolatedGit ? fixture.git : nil)
}

/// The demo world, scanned once.
@MainActor
func scannedDemoWorld() async throws -> (DemoWorld, AppModel, WorktreesModel) {
    let world = try await DemoWorld.build()
    let app = makeApp(world.fixture)
    await app.refresh()
    return (world, app, WorktreesModel(app: app))
}

extension WorktreesModel {
    func row(_ url: URL) -> WorktreeRow? {
        allRows.first { CanonicalPath.same($0.url, url) }
    }

    func ids(_ urls: [URL]) -> Set<WorktreeRow.ID> {
        Set(urls.compactMap { row($0)?.id })
    }
}

extension DemoWorld {
    /// The item's folder; fails the test with a clear message when the world has no such item.
    func url(_ name: String) throws -> URL {
        guard let item = item(named: name) else {
            throw SetupError(description: "the demo world has no \(name)")
        }
        return item.url
    }
}

/// The `clean-claude` binary the test run built (the test target depends on it).
enum CLIBinary {
    static func url(file: String = #filePath) throws -> URL {
        let packageRoot = URL(fileURLWithPath: file)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
            + [packageRoot.appending(path: ".build/debug")]
        for folder in folders {
            let candidate = folder.appending(path: "clean-claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw SetupError(description: "clean-claude binary not found in \(folders.map(\.path))")
    }
}

struct SetupError: Error, CustomStringConvertible {
    var description: String
}
