import Foundation

/// The processes running at one moment: one `/bin/ps -axo pid=,comm=,args=` run (PLAN §4.6), plus, in the app,
/// whether NSWorkspace lists Cursor. The scanner takes one per scan and the cleaner a fresh one per entry.
///
/// ps pads or cuts `comm` to exactly 16 characters when it is not the last column (`/opt/homebrew/Ce`), and a
/// program may rewrite its own title (npm shows `npm exec jest …`), so `comm` is trusted only when it is
/// shorter than that. Each process's executable path comes from the kernel (`proc_pidpath`), so a tool under a
/// folder with spaces (`…/My Tools/bin/npm`, which args can't split back) is still named; the command line in
/// `args` is what the argument rules look at.
public struct ProcessList: Sendable, Hashable {
    public struct Process: Sendable, Hashable {
        public var pid: Int32
        /// `comm` as ps printed it (at most 16 characters, trailing padding removed).
        public var command: String
        /// `args`: the whole command line, words joined by spaces (so a path with spaces can't be split back).
        public var arguments: String
        /// The executable's full path (`proc_pidpath`); nil when it couldn't be read (the process ended).
        public var executable: String?

        public init(pid: Int32, command: String, arguments: String, executable: String? = nil) {
            self.pid = pid
            self.command = command
            self.arguments = arguments
            self.executable = executable
        }
    }

    public static let ps = URL(fileURLWithPath: "/bin/ps")
    public static let psArguments = ["-axo", "pid=,comm=,args="]
    /// How wide ps prints `comm` when another column follows it.
    static let commandWidth = 16

    public var processes: [Process]
    /// NSWorkspace lists an application with Cursor's bundle id (only the app checks this).
    public var cursorAppRunning: Bool
    /// Why the list couldn't be read: every owner then counts as possibly running.
    public var failure: String?

    public init(processes: [Process], cursorAppRunning: Bool = false, failure: String? = nil) {
        self.processes = processes
        self.cursorAppRunning = cursorAppRunning
        self.failure = failure
    }

    /// Runs `/bin/ps` through `runner`, then reads each listed process's executable path with `executablePath`.
    /// `cursorAppRunning`: the app's NSWorkspace check (nil in the CLI).
    public static func capture(
        runner: CommandRunner = .live,
        cursorAppRunning: (@Sendable () async -> Bool)? = nil,
        executablePath: @Sendable (Int32) -> String? = ProcessList.executablePath
    ) async -> ProcessList {
        let cursor = await cursorAppRunning?() ?? false
        let result: ProcessResult
        do {
            result = try await runner.run(ps, psArguments, timeout: .seconds(20))
        } catch {
            return ProcessList(processes: [], cursorAppRunning: cursor, failure: "ps could not be started: \(error)")
        }
        if result.timedOut {
            return ProcessList(processes: [], cursorAppRunning: cursor, failure: "ps timed out")
        }
        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ProcessList(processes: [], cursorAppRunning: cursor,
                               failure: "ps failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
        }
        let processes = parse(result.stdoutString).map { process in
            var named = process
            named.executable = executablePath(process.pid)
            return named
        }
        guard !processes.isEmpty else {
            return ProcessList(processes: [], cursorAppRunning: cursor, failure: "ps listed no processes")
        }
        return ProcessList(processes: processes, cursorAppRunning: cursor)
    }

    /// The executable's path from the kernel; nil when it can't be read (the process ended, or it is protected).
    public static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// One process per line: the pid, one space, `comm` in a 16-character column, one space, `args`. A line
    /// whose `comm` doesn't fit that column (a name with non-ASCII characters) keeps an empty `command` and
    /// everything after the pid as `arguments`, so the command-line rules still see all of it.
    public static func parse(_ output: String) -> [Process] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop { $0 == " " }
            let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let pid = Int32(digits) else { return nil }
            var rest = trimmed.dropFirst(digits.count)
            guard rest.first == " " else { return nil }
            rest = rest.dropFirst()
            let column = rest.prefix(commandWidth)
            if column.count == commandWidth, rest.dropFirst(commandWidth).first == " " {
                let command = String(column).trimmingTrailingSpaces
                return Process(pid: pid, command: command, arguments: String(rest.dropFirst(commandWidth + 1)))
            }
            if rest.count <= commandWidth + 1 {
                // A short line: `comm` only, no arguments to show.
                let command = String(rest).trimmingTrailingSpaces
                return Process(pid: pid, command: command, arguments: command)
            }
            return Process(pid: pid, command: "", arguments: String(rest))
        }
    }
}

extension String {
    var trimmingTrailingSpaces: String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
