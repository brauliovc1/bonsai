import Foundation

/// The working folder of every process the user can see, from one `lsof -d cwd -Fpcn` per scan.
///
/// lsof only sees processes the user may inspect (not other users' or root's); that is a known limit.
/// When lsof is missing, fails or times out, the index is unavailable and every worktree gets an
/// "in use: unknown" reason that keeps auto mode away.
public struct ProcessCwdIndex: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Codable, CustomStringConvertible {
        public var pid: Int32
        public var command: String
        /// The process's working folder, lsof's escapes decoded (symlinks resolved by the kernel).
        public var cwd: String
        /// Other readings of an ambiguous lsof name: `^A` is how lsof prints byte 0x01, but also a literal
        /// `^A`. Matching tries `cwd` and each of these.
        public var alternativeCwds: [String]

        public init(pid: Int32, command: String, cwd: String, alternativeCwds: [String] = []) {
            self.pid = pid
            self.command = command
            self.cwd = cwd
            self.alternativeCwds = alternativeCwds
        }

        public var description: String { "\(command) (pid \(pid))" }
    }

    /// nil = unavailable.
    public var entries: [Entry]?
    /// Why the index is unavailable, when it is.
    public var failure: String?

    public init(entries: [Entry]) {
        self.entries = entries
        self.failure = nil
    }

    public static func unavailable(_ reason: String) -> ProcessCwdIndex {
        var index = ProcessCwdIndex(entries: [])
        index.entries = nil
        index.failure = reason
        return index
    }

    public var isAvailable: Bool { entries != nil }

    public static let arguments = ["-d", "cwd", "-Fpcn"]

    /// Runs the environment's lsof once, with the environment's timeout.
    public static func capture(in environment: CleanEnvironment) async -> ProcessCwdIndex {
        await capture(lsof: environment.tools.lsof, timeout: environment.timeouts.lsof)
    }

    /// Runs lsof once.
    public static func capture(lsof: URL?, timeout: Duration = .seconds(30)) async -> ProcessCwdIndex {
        guard let lsof else { return .unavailable("lsof not found") }
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(executable: lsof, arguments: arguments, timeout: timeout)
        } catch {
            return .unavailable("lsof could not start: \(error.localizedDescription)")
        }
        if result.timedOut { return .unavailable("lsof timed out") }
        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable("lsof failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
        }
        return ProcessCwdIndex(entries: parse(result.stdout))
    }

    /// Parses `-F pcn` output: `p<pid>`, `c<command>`, `f<fd>`, `n<path>` lines; a `p` line starts a process.
    public static func parse(_ data: Data) -> [Entry] {
        var entries: [Entry] = []
        var pid: Int32?
        var command = ""
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = LsofEscapes.decode(value).first ?? value
            case "n":
                guard let pid else { break }
                let readings = LsofEscapes.decode(value)
                entries.append(Entry(pid: pid, command: command, cwd: readings[0], alternativeCwds: Array(readings.dropFirst())))
            default:
                break
            }
        }
        return entries
    }

    /// Processes whose working folder is `folder` or inside it. Empty when the index is unavailable;
    /// check `isAvailable` first.
    ///
    /// Compared byte for byte after NFC normalization, so "é" matches whether it was stored composed or not.
    public func processes(inside folder: URL) -> [Entry] {
        guard let entries else { return [] }
        let bases = Set([CanonicalPath.resolve(folder), folder.standardized.path].map(Self.comparable))
        return entries.filter { entry in
            ([entry.cwd] + entry.alternativeCwds).map(Self.comparable).contains { cwd in
                bases.contains { base in cwd == base || cwd.starts(with: base == [0x2F] ? [0x2F] : base + [0x2F]) }
            }
        }
    }

    /// NFC UTF-8 bytes: Swift's `String ==` ignores normalization, but byte prefixes are exact.
    private static func comparable(_ path: String) -> [UInt8] {
        Array(path.precomposedStringWithCanonicalMapping.utf8)
    }
}
