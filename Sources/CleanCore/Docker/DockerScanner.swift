import Foundation

/// Finds out whether Docker Desktop is installed and running, how big its disk image is, and what
/// `docker system df` reports. Read-only: nothing here changes Docker.
public struct DockerScanner: Sendable {
    public var environment: CleanEnvironment
    public var runner: CommandRunner
    /// How long the daemon gets to answer `docker info`.
    public var infoTimeout: Duration
    public var usageTimeout: Duration

    public init(
        environment: CleanEnvironment,
        runner: CommandRunner = .live,
        infoTimeout: Duration = .seconds(5),
        usageTimeout: Duration = .seconds(30)
    ) {
        self.environment = environment
        self.runner = runner
        self.infoTimeout = infoTimeout
        self.usageTimeout = usageTimeout
    }

    static let infoArguments = ["info", "--format", "{{.ServerVersion}}"]
    static let usageArguments = ["system", "df", "--format", "{{json .}}"]

    public func scan() async -> DockerReport {
        var warnings: [String] = []
        let diskImage = await findDiskImage(warnings: &warnings)

        guard let docker = environment.tools.docker else {
            return DockerReport(state: .notInstalled, diskImage: diskImage, warnings: warnings)
        }

        guard let serverVersion = await serverVersion(docker: docker, warnings: &warnings) else {
            return DockerReport(state: .notRunning, diskImage: diskImage, warnings: warnings)
        }

        var usage: [DockerUsageRow] = []
        do {
            let result = try await runner.run(docker, Self.usageArguments, timeout: usageTimeout)
            if result.succeeded {
                let parsed = DockerUsageRow.parse(result.stdoutString)
                usage = parsed.rows
                if parsed.skippedLines > 0 {
                    warnings.append("docker system df: skipped \(parsed.skippedLines) line(s) it could not read")
                }
            } else {
                warnings.append("docker system df \(Self.failure(result))")
            }
        } catch {
            warnings.append("docker system df could not start: \(error)")
        }
        return DockerReport(
            state: .running,
            serverVersion: serverVersion,
            diskImage: diskImage,
            usage: usage,
            warnings: warnings
        )
    }

    /// The daemon's version when `docker info` succeeds within the timeout and prints one; nil otherwise.
    private func serverVersion(docker: URL, warnings: inout [String]) async -> String? {
        let result: ProcessResult
        do {
            result = try await runner.run(docker, Self.infoArguments, timeout: infoTimeout)
        } catch {
            warnings.append("docker could not start: \(error)")
            return nil
        }
        guard result.succeeded else { return nil }
        let version = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private static func failure(_ result: ProcessResult) -> String {
        if result.timedOut { return "timed out" }
        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)")
    }

    // MARK: Docker.raw

    /// `<home>/Library/Containers/com.docker.docker/Data/vms/*/data/Docker.raw`; the largest when there
    /// is more than one.
    private func findDiskImage(warnings: inout [String]) async -> DockerReport.DiskImage? {
        let vms = environment.homeDirectory
            .appending(path: "Library/Containers/com.docker.docker/Data/vms", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: vms.path) else { return nil }

        let images = entries.sorted()
            .map { vms.appending(path: $0).appending(path: "data/Docker.raw") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        var best: DockerReport.DiskImage?
        for image in images {
            guard let bytes = await allocatedBytes(of: image, warnings: &warnings) else { continue }
            if bytes > (best?.allocatedBytes ?? -1) {
                best = DockerReport.DiskImage(path: image.path, allocatedBytes: bytes)
            }
        }
        return best
    }

    /// Allocated bytes through `du`; if `du` is missing or fails, the file system's own allocated size.
    private func allocatedBytes(of image: URL, warnings: inout [String]) async -> Int64? {
        if let du = environment.tools.du {
            do {
                if let bytes = try await DirectorySizer(du: du).allocatedSize(ofItem: image) { return bytes }
            } catch {
                warnings.append("could not measure \(image.path) with du: \(error)")
            }
        }
        let values = try? image.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        if let allocated = values?.totalFileAllocatedSize { return Int64(allocated) }
        warnings.append("could not measure \(image.path)")
        return nil
    }
}
