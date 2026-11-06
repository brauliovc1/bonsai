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
        /// The process's working folder as lsof prints it (symlinks resolved by the kernel).
        public var cwd: String

        public init(pid: Int32, command: String, cwd: String) {
            self.pid = pid
            self.command = command
            self.cwd = cwd
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
                command = value
            case "n":
                if let pid { entries.append(Entry(pid: pid, command: command, cwd: value)) }
            default:
                break
            }
        }
        return entries
    }

    /// Processes whose working folder is `folder` or inside it. Empty when the index is unavailable;
    /// check `isAvailable` first.
    public func processes(inside folder: URL) -> [Entry] {
        guard let entries else { return [] }
        let bases = Set([CanonicalPath.resolve(folder), folder.standardized.path])
        return entries.filter { entry in
            bases.contains { base in entry.cwd == base || entry.cwd.hasPrefix(base == "/" ? "/" : base + "/") }
        }
    }
}
