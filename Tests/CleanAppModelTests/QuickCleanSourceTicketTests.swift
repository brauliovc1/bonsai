@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Quick clean bounded source tickets", .serialized)
@MainActor
struct QuickCleanSourceTicketTests {
    @Test func registrationChangeDuringListingCannotProduceAValidTicket() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.app.refresh()
        let gate = try QuickCleanListingGate(world.fixture)
        defer { gate.open() }
        var git = world.fixture.git; git.executable = gate.executable
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: git, roots: world.app.roots,
            repositories: world.app.scan?.repos ?? [], worktrees: world.app.scan?.worktrees ?? [])
        let cache = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        try gate.arm()
        let validating = Task { await fence.validate(paths: [cache.path]) }
        try #require(await eventually { gate.reached })
        let moved = world.fixture.scanRoot.appending(path: "still-outside-cache")
        try await world.fixture.run(["worktree", "move", world.old.path, moved.path], in: world.main)
        gate.open()
        let result = await validating.value
        #expect(result.problem?.contains("changed") == true && result.ticket == nil)
    }

    @Test func ticketTracksRegistrationsButDoesNotReadCommitObjectsOrIndex() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.app.refresh()
        let fence = world.quick.sourceFence
        let cache = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        let checked = await fence.validate(paths: [cache.path])
        let ticket = try #require(checked.ticket)
        #expect(checked.problem == nil && ticket.problemNow() == nil)
        let aged = AgedRepos(fixture: world.fixture, now: world.now)
        try world.fixture.write("new source\n", to: "source.txt", in: world.main)
        try await aged.git(["commit", "--quiet", "-am", "Change source without moving it"], in: world.main, days: 8)
        #expect(ticket.problemNow() == nil)
        let moved = world.fixture.scanRoot.appending(path: "new-registration-path")
        try await world.fixture.run(["worktree", "move", world.old.path, moved.path], in: world.main)
        #expect(ticket.problemNow() != nil)
    }

    @Test func gitDirectoryPointerPreservesPathWhitespace() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let repo = try await world.fixture.makeRepo("pointer-source")
        let storage = world.app.environment.homeDirectory.appending(path: "git storage ")
        try FileManager.default.moveItem(at: repo.appending(path: ".git"), to: storage)
        try Data("gitdir: \(storage.path)\n".utf8).write(to: repo.appending(path: ".git"))
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: world.fixture.git,
            roots: [], repositories: [repo.path], worktrees: [])
        let snapshot = try QuickCleanSourceSnapshot.capture(fence)
        #expect(snapshot.entries[storage.path + "/config"]?.bytes != nil)
    }

    @Test func oversizedMetadataRefusesRatherThanReadingAnUnboundedFile() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let config = world.main.appending(path: ".git/config")
        var bytes = try Data(contentsOf: config)
        bytes.append(Data(("\n#" + String(repeating: "x", count: 70_000) + "\n").utf8))
        try bytes.write(to: config)
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: world.fixture.git,
            roots: [], repositories: [world.main.path], worktrees: [])
        let cache = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        let result = await fence.validate(paths: [cache.path])
        #expect(result.problem?.contains("size limit") == true && result.ticket == nil)
    }

    @Test func missingTicketIsNeverAnAdmission() {
        #expect(QuickCleanSourceValidation(problem: nil, ticket: nil).problemNow() != nil)
    }

    @Test func invalidUTF8RegistrationNamesCannotAliasAReplacementCharacterName() throws {
        let valid = Array("bad-\u{FFFD}".utf8)
        let invalid: [UInt8] = Array("bad-".utf8) + [0xFF]
        #expect(try QuickCleanSourceSnapshot.registrationName(valid) == "bad-\u{FFFD}")
        var refused = false
        do { _ = try QuickCleanSourceSnapshot.registrationName(invalid) } catch { refused = true }
        #expect(refused, "A lossy UTF-8 key must not cause one registration to hide another.")
    }


    @Test func sourceMovingDuringTheLastOwnerCaptureInvalidatesTheCacheTicket() async throws {
        let scripted = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: ScriptedProcesses.idle) }
        let source = ProcessSource { await ProcessList.capture(runner: scripted.runner, executablePath: { _ in nil }) }
        let world = try await QuickCleanTestWorld.make(processes: source)
        defer { world.remove() }
        // Keep this worktree out of whole removal, while its old activity still permits dependency cleanup.
        try world.fixture.write("private draft\n", to: "draft.txt", in: world.old)
        try await AgedRepos(fixture: world.fixture, now: world.now).age(world.old, days: 8)
        let home = world.app.environment.homeDirectory
        let cache = home.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appending(path: "payload"))
        await world.quick.begin()
        try #require(world.group(.toolCaches).contains { $0.id == "cache:npm" })
        let gate = CallGate()
        defer { gate.release() }
        scripted.hold = gate.hold { $0.executable == ProcessList.ps }
        let task = try #require(world.quick.confirm())
        try #require(await eventually { gate.isReached })
        let newTarget = home.appending(path: ".npm/_npx")
        try FileManager.default.createDirectory(at: newTarget, withIntermediateDirectories: true)
        let moved = newTarget.appending(path: "protected-draft")
        try await world.fixture.run(["worktree", "move", world.old.path, moved.path], in: world.main)
        gate.release()
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(moved.appending(path: "draft.txt")) && world.exists(moved.appending(path: ".git")))
        #expect(world.exists(cache.appending(path: "payload")))
        #expect(task.items.first { $0.resources.contains("cache:npm") }?.state == .refused)
    }

}
