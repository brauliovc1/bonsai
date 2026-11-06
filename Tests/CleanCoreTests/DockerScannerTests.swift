@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("DockerScanner")
struct DockerScannerTests {
    private static let docker = URL(fileURLWithPath: "/fake/bin/docker")
    private static let infoArguments = ["info", "--format", "{{.ServerVersion}}"]
    private static let systemArguments = ["info", "--format", "{{.OperatingSystem}}"]
    private static let dfArguments = ["system", "df", "--format", "{{json .}}"]

    private static let dfOutput = """
        {"Active":"3","Reclaimable":"5.2GB (62%)","Size":"8.4GB","TotalCount":"12","Type":"Images"}
        {"Active":"1","Reclaimable":"0B (0%)","Size":"1.2kB","TotalCount":"1","Type":"Containers"}
        {"Active":"2","Reclaimable":"512MB","Size":"3.4GB","TotalCount":"4","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
        """

    /// A fake docker: `info` (version), `info` (operating system) and `system df` answer with the given results.
    private func script(
        info: ProcessResult,
        system: ProcessResult = ScriptedCommandRunner.result(stdout: "Docker Desktop\n"),
        df: ProcessResult = ScriptedCommandRunner.result()
    ) -> ScriptedCommandRunner {
        ScriptedCommandRunner { call in
            switch call.arguments {
            case Self.infoArguments: info
            case Self.systemArguments: system
            case Self.dfArguments: df
            default: throw ScriptedCommandRunner.StartFailure()
            }
        }
    }

    @Test func dockerBinaryMissingMeansNotInstalledAndRunsNothing() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(info: ScriptedCommandRunner.result(stdout: "27.0.1"))

        let report = await DockerScanner(environment: home.environment(docker: nil), runner: runner.runner).scan()

        #expect(report.state == .notInstalled)
        #expect(report.usage.isEmpty && report.diskImage == nil && report.serverVersion == nil)
        #expect(runner.calls.isEmpty)
        #expect(report.pruneBlocker != nil)
    }

    @Test func infoTimingOutMeansNotRunningAndSaysWhy() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(info: ScriptedCommandRunner.result(exitCode: 15, timedOut: true))

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .notRunning)
        #expect(report.usage.isEmpty)
        #expect(report.notRunningReason == "docker info did not answer within 5 s")
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1)
        #expect(call.executable == Self.docker)
        #expect(call.arguments == Self.infoArguments)
        #expect(call.timeout == .seconds(5))
        #expect(report.pruneBlocker != nil)
    }

    @Test func infoFailingMeansNotRunningAndKeepsDockersMessage() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(info: ScriptedCommandRunner.result(
            exitCode: 1,
            stderr: "Cannot connect to the Docker daemon at unix:///var/run/docker.sock\nIs the daemon running?"
        ))

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .notRunning)
        #expect(report.notRunningReason == "docker info failed (exit 1): Cannot connect to the Docker daemon at unix:///var/run/docker.sock")
        #expect(runner.calls.map(\.arguments) == [Self.infoArguments], "nothing else runs against a dead daemon")
    }

    @Test func infoThatPrintsNothingIsNotRunning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(info: ScriptedCommandRunner.result(exitCode: 0, stdout: "  \n"))

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .notRunning)
        #expect(report.notRunningReason == "docker info printed no server version")
    }

    @Test func aBinaryThatCannotStartIsNotRunningWithAWarning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .notRunning)
        #expect(report.notRunningReason == "docker could not be started")
        #expect(report.warnings.count == 1)
    }

    @Test func runningDaemonReportsVersionIdentityAndUsage() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(
            info: ScriptedCommandRunner.result(stdout: "27.3.1\n"),
            df: ScriptedCommandRunner.result(stdout: Self.dfOutput + "\nnot json at all\n")
        )

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .running)
        #expect(report.serverVersion == "27.3.1")
        #expect(report.daemonOperatingSystem == "Docker Desktop")
        #expect(report.isDockerDesktop)
        #expect(report.pruneBlocker == nil)
        #expect(report.notRunningReason == nil)
        #expect(report.usage.map(\.type) == ["Images", "Containers", "Local Volumes", "Build Cache"])
        let images = try #require(report.usage.first)
        #expect(images.sizeBytes == 8_400_000_000)
        #expect(images.reclaimableBytes == 5_200_000_000)
        #expect(report.warnings.count == 1, "the malformed line is reported, not fatal")
        #expect(runner.calls.map(\.arguments) == [Self.infoArguments, Self.systemArguments, Self.dfArguments])
        #expect(runner.calls.allSatisfy { $0.executable == Self.docker })
    }

    @Test func aDaemonThatIsNotDockerDesktopBlocksPruning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        // What DOCKER_HOST or a docker context pointing at a Linux host would look like.
        let runner = script(
            info: ScriptedCommandRunner.result(stdout: "26.1.4\n"),
            system: ScriptedCommandRunner.result(stdout: "Ubuntu 22.04.4 LTS\n"),
            df: ScriptedCommandRunner.result(stdout: Self.dfOutput)
        )

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .running)
        #expect(report.daemonOperatingSystem == "Ubuntu 22.04.4 LTS")
        #expect(!report.isDockerDesktop)
        let blocker = try #require(report.pruneBlocker)
        #expect(blocker.contains("Ubuntu 22.04.4 LTS") && blocker.contains("DOCKER_HOST"))
    }

    @Test func aDaemonThatCannotNameItselfBlocksPruning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(
            info: ScriptedCommandRunner.result(stdout: "27.3.1"),
            system: ScriptedCommandRunner.result(exitCode: 1, stderr: "boom"),
            df: ScriptedCommandRunner.result(stdout: Self.dfOutput)
        )

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .running)
        #expect(report.daemonOperatingSystem == nil)
        #expect(report.pruneBlocker != nil)
        #expect(report.warnings.count == 1)
        #expect(report.usage.count == 4, "usage is still shown")
    }

    @Test func aFailingDfLeavesARunningReportWithAWarning() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(
            info: ScriptedCommandRunner.result(stdout: "27.3.1"),
            df: ScriptedCommandRunner.result(exitCode: 1, stderr: "boom")
        )

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .running)
        #expect(report.usage.isEmpty)
        #expect(report.warnings.first?.contains("boom") == true)
    }

    @Test func neverRunsAnythingButReadOnlyInfoAndDf() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(
            info: ScriptedCommandRunner.result(stdout: "27.3.1"),
            df: ScriptedCommandRunner.result(stdout: Self.dfOutput)
        )

        _ = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(!runner.calls.isEmpty, "the check below would otherwise pass without checking anything")
        for call in runner.calls {
            #expect(!call.arguments.contains("prune"))
            #expect(call.arguments.first == "info" || call.arguments.starts(with: ["system", "df"]))
        }
    }

    // MARK: Docker.raw

    private static let rawPath = "Library/Containers/com.docker.docker/Data/vms"

    @Test func findsDockerRawByGlobAndMeasuresAllocatedSize() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let raw = try home.addFile("\(Self.rawPath)/0/data/Docker.raw", kibibytes: 64)
        try home.addFolder("\(Self.rawPath)/1/data")
        try home.addFile("\(Self.rawPath)/2/data/other.txt", kibibytes: 4)

        let report = await DockerScanner(environment: home.environment(docker: nil)).scan()

        #expect(report.state == .notInstalled, "Docker.raw is reported even without the CLI")
        let image = try #require(report.diskImage)
        #expect(CanonicalPath.same(URL(fileURLWithPath: image.path), raw))
        #expect(image.allocatedBytes == 64 * 1024)
        #expect(report.warnings.isEmpty)
    }

    @Test func picksTheLargestDockerRawWhenThereAreSeveral() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile("\(Self.rawPath)/0/data/Docker.raw", kibibytes: 8)
        let bigger = try home.addFile("\(Self.rawPath)/1/data/Docker.raw", kibibytes: 32)

        let report = await DockerScanner(environment: home.environment()).scan()

        let image = try #require(report.diskImage)
        #expect(CanonicalPath.same(URL(fileURLWithPath: image.path), bigger))
        #expect(image.allocatedBytes == 32 * 1024)
    }

    @Test func aSymlinkedDockerRawIsMeasuredAsItsTarget() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let target = try home.addFile("elsewhere/Docker.raw", kibibytes: 48)
        try home.addFolder("\(Self.rawPath)/0/data")
        try FileManager.default.createSymbolicLink(
            at: home.url.appending(path: "\(Self.rawPath)/0/data/Docker.raw"),
            withDestinationURL: target
        )

        let report = await DockerScanner(environment: home.environment()).scan()

        #expect(report.diskImage?.allocatedBytes == Int64(48 * 1024), "du alone reports a symlink as 0")
    }

    @Test func noDockerRawMeansNoDiskImage() async throws {
        let home = try FakeHome()
        defer { home.remove() }

        #expect(await DockerScanner(environment: home.environment()).scan().diskImage == nil)

        try home.addFolder("\(Self.rawPath)/0/data")
        #expect(await DockerScanner(environment: home.environment()).scan().diskImage == nil)
    }

    @Test func anUnreadableVMsFolderIsAWarningNotASilentNotFound() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let vms = try home.addFolder(Self.rawPath)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vms.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vms.path) }

        let report = await DockerScanner(environment: home.environment()).scan()

        #expect(report.diskImage == nil)
        #expect(report.warnings.count == 1)
        #expect(report.warnings.first?.contains("could not read") == true)
    }

    @Test func aDownDaemonStillShowsTheDiskImage() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile("\(Self.rawPath)/0/data/Docker.raw", kibibytes: 16)
        let runner = script(info: ScriptedCommandRunner.result(exitCode: 1))

        let report = await DockerScanner(environment: home.environment(docker: Self.docker), runner: runner.runner).scan()

        #expect(report.state == .notRunning)
        #expect(report.diskImage?.allocatedBytes == Int64(16 * 1024))
    }

    @Test func reportSurvivesAJSONRoundTrip() throws {
        let report = DockerReport(
            state: .running,
            serverVersion: "27.3.1",
            daemonOperatingSystem: "Docker Desktop",
            notRunningReason: nil,
            diskImage: .init(path: "/x/Docker.raw", allocatedBytes: 5),
            usage: [DockerUsageRow(type: "Images", total: 1, active: 1, sizeBytes: 2, reclaimableBytes: 1)],
            warnings: ["w"]
        )
        let data = try CleanJSON.encoder().encode(report)
        #expect(try CleanJSON.decoder().decode(DockerReport.self, from: data) == report)
    }
}
