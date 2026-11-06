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
    /// `Docker.raw`, found whether or not the daemon is up.
    public var diskImage: DiskImage?
    /// Empty unless the daemon is running.
    public var usage: [DockerUsageRow]
    /// Things that went wrong without stopping the scan (a failed `docker system df`, a skipped line).
    public var warnings: [String]

    public init(
        state: State,
        serverVersion: String? = nil,
        diskImage: DiskImage? = nil,
        usage: [DockerUsageRow] = [],
        warnings: [String] = []
    ) {
        self.state = state
        self.serverVersion = serverVersion
        self.diskImage = diskImage
        self.usage = usage
        self.warnings = warnings
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
