@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Docker model")
@MainActor
struct DockerModelTests {
    // MARK: - Docker states

    @Test func dockerNotInstalled() async throws {
        let world = try DockerSimulatorsWorld(docker: false)
        defer { world.home.remove() }
        await world.model.refresh()

        #expect(world.model.dockerStatus == .notInstalled)
        #expect(world.model.dockerStatusText == "Docker isn't installed.")
        #expect(!world.model.canPrune)
        #expect(world.model.pruneDisabledReason == world.model.docker?.pruneBlocker)
        #expect(world.model.pruneDisabledReason != nil)
        #expect(world.model.dockerReclaimableBytes == nil)
        #expect(world.toolchain.calls.filter { $0.executable == FakeToolchain.docker }.isEmpty)
    }

    @Test func dockerNotRunningShowsTheDiskImageAndStartDocker() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        world.toolchain.dockerRunning = false
        try world.home.addFile("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", kibibytes: 64)
        await world.model.refresh()

        #expect(world.model.dockerStatus == .notRunning)
        #expect(world.model.dockerStatusText == "Docker isn't running.")
        #expect(world.model.dockerDiskImageText == "Docker.raw: 64.0 KB on disk")
        #expect(world.model.startDockerHint == "Start Docker to clean.")
        #expect(world.model.dockerUsage.isEmpty)
        #expect(!world.model.canPrune)
        #expect(world.model.pruneDisabledReason == world.model.docker?.pruneBlocker)
        #expect(world.model.pruneDisabledReason?.contains("Start Docker Desktop") == true)
        #expect(world.model.dockerReclaimableBytes == nil)
    }

    @Test func dockerRunningShowsTheDfTableAndWhatPruneCanFree() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.refresh()

        #expect(world.model.dockerStatus == .running)
        #expect(world.model.dockerStatusText == "Docker Desktop is running (engine 27.0.1).")
        #expect(world.model.dockerUsage.map(\.type) == ["Images", "Containers", "Local Volumes", "Build Cache"])
        #expect(world.model.dockerUsage.first?.countText == "12 (3 active)")
        #expect(world.model.startDockerHint == nil)
        #expect(world.model.canPrune)
        #expect(world.model.pruneDisabledReason == nil)
        let docker = try #require(world.model.docker)
        #expect(world.model.dockerReclaimableBytes == docker.pruneCeilingBytes)
        #expect(docker.pruneCeilingBytes < docker.reclaimableBytes, "volumes are left out of what prune can free")
        #expect(docker.pruneCeilingBytes > 0)
    }

    @Test func pruneIsDisabledWithTheReasonWhenTheDaemonIsNotDockerDesktop() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        world.toolchain.daemonOS = "Colima"
        await world.model.refresh()

        #expect(world.model.dockerStatus == .running)
        #expect(!world.model.canPrune)
        let reason = try #require(world.model.pruneDisabledReason)
        #expect(reason == world.model.docker?.pruneBlocker)
        #expect(reason.contains("not Docker Desktop"), "\(reason)")

        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)
        #expect(!confirmation.isAllowed)
        #expect(confirmation.blocker == reason)
        let report = await world.model.confirmDockerPrune(confirmation)
        #expect(!report.didRun)
        #expect(report.summary.contains("not Docker Desktop"))
        #expect(world.toolchain.pruneCalls.isEmpty, "the cleaner is never asked")
        #expect(world.app.logEntries.isEmpty)
    }

    // MARK: - Docker prune

    @Test func theSheetCarriesTheExactCommandAndRunsOnlyThat() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.refresh()

        await world.model.beginDockerPrune()
        #expect(world.model.isShowingDockerSheet)
        let confirmation = try #require(world.model.dockerConfirmation)
        #expect(DockerPruneConfirmation.command == "docker system prune -f")
        #expect(confirmation.commandLine == "/fake/bin/docker system prune -f")
        #expect(DockerPruneConfirmation.removes.joined(separator: " ").contains("Stopped containers"))
        #expect(DockerPruneConfirmation.removes.joined(separator: " ").contains("Dangling images"))
        #expect(DockerPruneConfirmation.removes.joined(separator: " ").contains("Build cache"))
        #expect(DockerPruneConfirmation.keeps.joined(separator: " ").contains("Volumes"))
        #expect(DockerPruneConfirmation.keeps.joined(separator: " ").contains("Tagged images"))
        #expect(DockerPruneConfirmation.slowLine == "Docker Desktop can take a while to give the space back.")
        #expect(confirmation.isAllowed)
        #expect(confirmation.estimatedBytes == world.model.docker?.pruneCeilingBytes)
        #expect(world.toolchain.pruneCalls.isEmpty, "opening the sheet changes nothing")

        let report = await world.model.confirmDockerPrune(confirmation)

        let call = try #require(world.toolchain.pruneCalls.first)
        #expect(world.toolchain.pruneCalls.count == 1)
        #expect(call.executable == FakeToolchain.docker)
        #expect(call.arguments == ["system", "prune", "-f"], "no -a, no --volumes")
        #expect(report.didRun && report.succeeded)
        #expect(report.logError == nil)
        #expect(report.reportedBytes == 1_500_000_000, "docker's own number: 1.5GB, decimal")
        #expect(report.summary.contains("Docker Desktop can take a while to give the space back."))
        #expect(world.model.dockerReport?.succeeded == true)

        // CleanCore wrote the log entry; the screen read it and scanned again.
        let entry = try #require(world.app.logEntries.first)
        #expect(world.app.logEntries.count == 1)
        #expect(entry.action == .dockerPrune)
        #expect(entry.notes.contains("/fake/bin/docker system prune -f"))
        #expect(world.model.docker != nil)
    }

    @Test func aDaemonThatStoppedAfterTheSheetOpenedIsNotPruned() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)
        #expect(confirmation.isAllowed)

        world.toolchain.dockerRunning = false
        let report = await world.model.confirmDockerPrune(confirmation)

        #expect(!report.didRun)
        #expect(report.error?.contains("not running") == true, "\(report.error ?? "")")
        #expect(world.toolchain.pruneCalls.isEmpty)
        #expect(world.app.logEntries.isEmpty)
    }

    @Test func aDaemonThatBecameAnotherEngineAfterTheSheetOpenedIsNotPruned() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)

        world.toolchain.daemonOS = "OrbStack"
        let report = await world.model.confirmDockerPrune(confirmation)

        #expect(!report.didRun)
        #expect(world.toolchain.pruneCalls.isEmpty)
    }

    @Test func aLogWriteFailureIsShownNotSwallowed() async throws {
        // The settings folder sits below a file, so the log can't be created.
        var blocker: URL?
        let world = try DockerSimulatorsWorld { environment in
            let file = environment.homeDirectory.appending(path: "blocker")
            blocker = file
            environment.settingsDirectory = file.appending(path: "settings", directoryHint: .isDirectory)
        }
        defer { world.home.remove() }
        try Data("a file".utf8).write(to: try #require(blocker))
        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)

        let report = await world.model.confirmDockerPrune(confirmation)

        #expect(world.toolchain.pruneCalls.count == 1, "the command ran")
        #expect(report.succeeded)
        let logError = try #require(report.logError, "the failed log write is part of the report")
        #expect(logError.contains("not logged"), "\(logError)")
        #expect(world.app.logEntries.isEmpty)
    }

    /// Wave 4: a second confirm while the prune runs is turned away without touching the running one.
    @Test func aSecondConfirmWhilePruningLeavesItsProgressAlone() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)
        let gate = CallGate()
        world.toolchain.onCall = gate.hold { $0.arguments == ["system", "prune", "-f"] }
        defer { gate.release() }

        let first = Task { await world.model.confirmDockerPrune(confirmation) }
        try await gate.waitUntilReached()
        #expect(world.model.isPruning)
        #expect(world.model.dockerReport == nil)

        let second = await world.model.confirmDockerPrune(confirmation)

        #expect(!second.didRun)
        #expect(second.error?.contains("already running") == true, "\(second.error ?? "")")
        #expect(world.model.dockerReport == nil, "the progress page is still showing")
        #expect(world.model.isPruning)

        gate.release()
        let report = await first.value
        #expect(report.didRun && report.succeeded)
        #expect(world.model.dockerReport?.didRun == true)
        #expect(world.toolchain.pruneCalls.count == 1)
    }

    @Test func oneCleanupAtATime() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginDockerPrune()
        let confirmation = try #require(world.model.dockerConfirmation)

        let finished = await world.app.cleaningUp {
            await world.model.confirmDockerPrune(confirmation)
        }
        // The nested prune was refused: another cleanup (this closure) was running.
        let report = try #require(finished)
        #expect(!report.didRun)
        #expect(report.error?.contains("Another cleanup") == true, "\(report.error ?? "")")
        #expect(world.toolchain.pruneCalls.isEmpty)
    }
}
