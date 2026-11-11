@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@MainActor
struct QuickCleanListingGate {
    let folder: URL
    var executable: URL { folder.appending(path: "git") }
    var reached: Bool { FileManager.default.fileExists(atPath: folder.appending(path: "waiting").path) }

    init(_ fixture: GitFixture) throws {
        folder = fixture.url.appending(path: "source-list-gate")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = """
        #!/bin/sh
        G='\(folder.path)'
        case " $* " in
          *" worktree list "*)
            if [ -e "$G/armed" ]; then
              rm -f "$G/armed"
              touch "$G/waiting"
              n=0
              while [ ! -e "$G/released" ] && [ "$n" -lt \(Int(TestWait.seconds / 0.02)) ]; do sleep 0.02; n=$((n + 1)); done
              [ -e "$G/released" ] || exit 1
            fi ;;
        esac
        exec '\(fixture.git.executable.path)' "$@"
        """
        try text.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func arm() throws { try Data().write(to: folder.appending(path: "armed")) }
    func open() { try? Data().write(to: folder.appending(path: "released")) }
}

@Suite("Quick clean safety ordering", .serialized)
@MainActor
struct QuickCleanOrderingRegressionTests {
    @Test(arguments: [false, true])
    func sourceFenceDoesNotStaleTheOriginalOwnerOrDeviceChecks(simulators: Bool) async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let gate = try QuickCleanListingGate(fixture)
        defer { gate.open() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("source-outside-tools", days: 8, gitignore: "", files: ["source.swift": "keep\n"])
        try await aged.age(repo, days: 8)
        let environment = fixture.environment(scanRoots: [repo]).withFakeTools(docker: false, xcrun: simulators, developerTools: simulators)
        try SettingsStore(environment: environment).save(Settings(scanRoots: [repo.path], idleThresholdDays: 30))
        var git = fixture.git; git.executable = gate.executable
        let app = AppModel(environment: environment, git: git)
        let tools = FakeToolchain(), processes = ScriptedProcesses()
        let models = ScreenModels(app: app, runner: tools.runner, processes: processes.source)
        let cache = environment.homeDirectory.appending(path: ".npm/_cacache")
        if !simulators {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("preserve while npm runs\n".utf8).write(to: cache.appending(path: "payload"))
        }
        await models.quickClean.begin()
        try #require(app.scan?.repos.count == 1)
        let kind: QuickCleanGroup.Kind = simulators ? .simulators : .toolCaches
        try #require(models.quickClean.preview?.groups.first { $0.id == kind }?.items.isEmpty == false)
        try gate.arm()
        let task = try #require(models.quickClean.confirm())
        try #require(await eventually { gate.reached || task.completedCount > 0 })
        try #require(gate.reached, "The runtime source re-list must be held, independently of whether it runs before or after the category's own check.")
        if simulators { tools.unavailable.append(("NEW-DURING-FENCE", "New unavailable", 128)) }
        else { processes.run("npm install") }
        gate.open()
        await app.cleanupQueue.waitUntilEmpty()

        if simulators {
            #expect(tools.deleteCalls.isEmpty, "The source fence must not leave the captured UDID comparison stale before delete unavailable.")
            #expect(task.items.first { $0.resources.contains(DockerSimulatorsModel.simulatorsResource) }?.state == .refused)
        } else {
            #expect(FileManager.default.fileExists(atPath: cache.appending(path: "payload").path), "The source fence must not leave the cache-owner snapshot stale.")
            #expect(task.items.first { $0.resources.contains("cache:npm") }?.state == .refused)
        }
    }
}
