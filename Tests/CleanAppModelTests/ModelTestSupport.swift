import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// An `AppModel` that scans `root` (default: the whole fixture) with settings and log inside the
/// fixture's home. `isolatedGit`: the fixture's git, which ignores the user's git config; false uses the
/// git the environment resolves, as the app and the CLI do.
@MainActor
func makeApp(_ fixture: GitFixture, root: URL? = nil, isolatedGit: Bool = true) -> AppModel {
    AppModel(environment: fixture.environment(scanRoots: [root ?? fixture.url]), git: isolatedGit ? fixture.git : nil)
}

/// The demo world, scanned once, its Worktrees model showing every worktree ("All").
@MainActor
func scannedDemoWorld() async throws -> (DemoWorld, AppModel, WorktreesModel) {
    let world = try await DemoWorld.build()
    let app = makeApp(world.fixture)
    await app.refresh()
    return (world, app, showingAll(WorktreesModel(app: app)))
}

/// The model with the "All" filter, so blocked, missing and stale rows are shown too.
@MainActor
func showingAll(_ model: WorktreesModel) -> WorktreesModel {
    model.filter = .all
    return model
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

/// The `bonsai` binary the test run built (the test target depends on it).
enum CLIBinary {
    static func url(file: String = #filePath) throws -> URL {
        let packageRoot = URL(fileURLWithPath: file)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
            + [packageRoot.appending(path: ".build/debug")]
        for folder in folders {
            let candidate = folder.appending(path: "bonsai")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw SetupError(description: "bonsai binary not found in \(folders.map(\.path))")
    }

    /// Runs it with `environment` added to the inherited one (`inheritedEnvironment` when given), in a slot of
    /// `ProcessLimit.helpers`. It may take as long as the machine needs, and the test says so when it doesn't finish.
    static func run(
        _ arguments: [String], environment: [String: String], inheritedEnvironment: [String: String]? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> ProcessResult {
        let executable = try url()
        let result = try await ProcessLimit.helpers.run {
            try await ProcessRunner.run(
                executable: executable, arguments: arguments, environmentAdditions: environment,
                inheritedEnvironment: inheritedEnvironment, timeout: TestWait.limit
            )
        }
        #expect(!result.timedOut, "bonsai \(arguments.joined(separator: " ")) didn't finish within \(TestWait.limit)",
                sourceLocation: sourceLocation)
        return result
    }
}

struct SetupError: Error, CustomStringConvertible {
    var description: String
}
