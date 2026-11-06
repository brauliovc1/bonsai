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
    static let systemArguments = ["info", "--format", "{{.OperatingSystem}}"]
    static let usageArguments = ["system", "df", "--format", "{{json .}}"]

    public func scan() async -> DockerReport {
        var warnings: [String] = []
        let diskImage = await findDiskImage(warnings: &warnings)

        guard let docker = environment.tools.docker else {
            return DockerReport(state: .notInstalled, diskImage: diskImage, warnings: warnings)
        }

        let answer = await probeServerVersion(docker: docker, warnings: &warnings)
        guard let serverVersion = answer.version else {
            return DockerReport(
                state: .notRunning,
                notRunningReason: answer.failure,
                diskImage: diskImage,
                warnings: warnings
            )
        }
        let operatingSystem = await daemonOperatingSystem(docker: docker, warnings: &warnings)

        var usage: [DockerUsageRow] = []
        var usageFailure: String?
        do {
            let result = try await runner.run(docker, Self.usageArguments, timeout: usageTimeout)
            if result.succeeded {
                let parsed = DockerUsageRow.parse(result.stdoutString)
                usage = parsed.rows
                if parsed.skippedLines > 0 {
                    warnings.append("docker system df: skipped \(parsed.skippedLines) line(s) it could not read")
                }
                if usage.isEmpty { usageFailure = "docker system df printed nothing that could be read" }
            } else {
                usageFailure = "docker system df \(Self.failure(result))"
                warnings.append(usageFailure ?? "")
            }
        } catch {
            usageFailure = "docker system df could not start: \(error)"
            warnings.append(usageFailure ?? "")
        }
        return DockerReport(
            state: .running,
            serverVersion: serverVersion,
            daemonOperatingSystem: operatingSystem,
            diskImage: diskImage,
            usage: usage,
            warnings: warnings,
            usageFailure: usageFailure
        )
    }

    /// The daemon's version when `docker info` succeeds within the timeout and prints one; otherwise why not.
    private func probeServerVersion(
        docker: URL,
        warnings: inout [String]
    ) async -> (version: String?, failure: String?) {
        let result: ProcessResult
        do {
            result = try await runner.run(docker, Self.infoArguments, timeout: infoTimeout)
        } catch {
            warnings.append("docker could not start: \(error)")
            return (nil, "docker could not be started")
        }
        if result.timedOut {
            return (nil, "docker info did not answer within \(infoTimeout.components.seconds) s")
        }
        guard result.succeeded else {
            let message = result.stderr.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return (nil, "docker info failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
        }
        let version = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? (nil, "docker info printed no server version") : (version, nil)
    }

    /// What the daemon says it runs on. nil (with a warning) when it cannot say, which counts as "not
    /// Docker Desktop" for the prune check.
    private func daemonOperatingSystem(docker: URL, warnings: inout [String]) async -> String? {
        do {
            let result = try await runner.run(docker, Self.systemArguments, timeout: infoTimeout)
            let text = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded, !text.isEmpty { return text }
            warnings.append("docker info could not tell which daemon this is; pruning stays blocked")
        } catch {
            warnings.append("docker info (daemon identity): \(error)")
        }
        return nil
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
        guard FileManager.default.fileExists(atPath: vms.path) else { return nil }
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: vms.path)
        } catch {
            // Usually macOS privacy (no access to ~/Library/Containers), not a missing disk image.
            warnings.append("could not read \(vms.path): \(error.localizedDescription)")
            return nil
        }

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
