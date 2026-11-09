import Foundation

/// What Docker Desktop is doing and where its disk space goes. Read-only.
public struct DockerReport: Sendable, Codable, Equatable {
    public enum State: String, Sendable, Codable {
        /// No docker binary in the known locations.
        case notInstalled
        /// The binary exists but the daemon did not answer `docker info` in time (or at all).
        case notRunning
        case running
    }

    /// Docker Desktop's disk image. It is a sparse file: only the allocated size counts.
    public struct DiskImage: Sendable, Codable, Equatable {
        public var path: String
        public var allocatedBytes: Int64

        public init(path: String, allocatedBytes: Int64) {
            self.path = path
            self.allocatedBytes = allocatedBytes
        }
    }

    public var state: State
    /// `docker info`'s server version, when the daemon answered.
    public var serverVersion: String?
    /// What the daemon says it runs on (`docker info`'s OperatingSystem): `Docker Desktop` for Docker
    /// Desktop, something else for a remote, Colima or OrbStack daemon, which `DOCKER_HOST` or a docker
    /// context can silently point the CLI at. nil when it was not asked or did not answer.
    public var daemonOperatingSystem: String?
    /// Why the daemon counts as not running: it timed out, failed (with docker's message) or printed
    /// nothing. nil in the other states.
    public var notRunningReason: String?
    /// `Docker.raw`, found whether or not the daemon is up.
    public var diskImage: DiskImage?
    /// Empty unless the daemon is running.
    public var usage: [DockerUsageRow]
    /// Things that went wrong without stopping the scan (a failed `docker system df`, a skipped line).
    public var warnings: [String]
    /// Why `usage` is empty although the daemon is running: `docker system df` failed or printed nothing
    /// readable. Without it, an empty `usage` means "nothing", with it "unknown".
    public var usageFailure: String?

    public init(
        state: State,
        serverVersion: String? = nil,
        daemonOperatingSystem: String? = nil,
        notRunningReason: String? = nil,
        diskImage: DiskImage? = nil,
        usage: [DockerUsageRow] = [],
        warnings: [String] = [],
        usageFailure: String? = nil
    ) {
        self.state = state
        self.serverVersion = serverVersion
        self.daemonOperatingSystem = daemonOperatingSystem
        self.notRunningReason = notRunningReason
        self.diskImage = diskImage
        self.usage = usage
        self.warnings = warnings
        self.usageFailure = usageFailure
    }

    /// The daemon identified itself as Docker Desktop, the only daemon Bonsai prunes (PLAN §7).
    public var isDockerDesktop: Bool {
        daemonOperatingSystem?.lowercased().hasPrefix("docker desktop") == true
    }

    /// Why `docker system prune -f` must not run now, or nil when it may. Every caller checks this: the
    /// CLI and the guarded `DockerCleaner.run(ifConfirmed:report:)`.
    public var pruneBlocker: String? {
        switch state {
        case .notInstalled:
            return "Docker is not installed, so there is nothing to prune."
        case .notRunning:
            return "Docker is not running. Start Docker Desktop, then run this again."
        case .running:
            guard isDockerDesktop else {
                let found = daemonOperatingSystem.map { "\"\($0)\"" } ?? "unknown"
                return "The Docker daemon reports itself as \(found), not Docker Desktop, and Bonsai only "
                    + "prunes Docker Desktop. Check DOCKER_HOST and your docker context (docker context show)."
            }
            return nil
        }
    }

    /// Everything `docker system df` calls reclaimable.
    public var reclaimableBytes: Int64 {
        usage.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// The most `docker system prune -f` can free: reclaimable minus Local Volumes, which `-f` without
    /// `--volumes` never touches. Still an upper bound: unused images that are tagged stay too.
    public var pruneCeilingBytes: Int64 {
        usage.filter { $0.type.lowercased() != "local volumes" }.reduce(0) { $0 + $1.reclaimableBytes }
    }
}
