import CleanCore
import Foundation

/// Canned `ps -axo pid=,comm=,args=` output for the tool-cache code: every capture runs the real parser on
/// `output` as it is at that moment, so a test can have an owner start between a scan and a clean. No test
/// runs the real ps through this.
public final class ScriptedProcesses: @unchecked Sendable {
    /// What an idle Mac might list: nothing that owns a cache.
    public static let idle = [
        line(pid: 1, arguments: "/sbin/launchd"),
        line(pid: 412, arguments: "/usr/libexec/logd"),
        line(pid: 880, arguments: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
        line(pid: 1204, arguments: "-zsh"),
        line(pid: 1890, arguments: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility"),
        line(pid: 2100, arguments: "node /Users/someone/project/node_modules/.bin/jest src/app.spec.ts"),
    ].joined(separator: "\n")

    private let lock = NSLock()
    private var current: String
    private var failing = false
    private var captures = 0
    private var cursorApp = false
    private var paths: [Int32: String] = [:]

    public init(_ output: String = ScriptedProcesses.idle) {
        current = output
    }

    /// The ps output the next capture sees.
    public var output: String {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    /// Adds lines to the idle output: `running("npm install")` -> a process `npm` with those arguments.
    public func run(_ lines: String...) {
        output = Self.idle + "\n" + lines.enumerated().map { index, line in Self.line(pid: 3000 + Int32(index), arguments: line) }
            .joined(separator: "\n")
    }

    /// The next captures fail as if ps exited 1.
    public var fails: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    /// What the app's NSWorkspace check answers for Cursor.
    public var cursorAppRunning: Bool {
        get { lock.withLock { cursorApp } }
        set { lock.withLock { cursorApp = newValue } }
    }

    public var captureCount: Int { lock.withLock { captures } }

    /// What `proc_pidpath` answers per pid (nil for any other pid, as for a process that ended).
    public var executables: [Int32: String] {
        get { lock.withLock { paths } }
        set { lock.withLock { paths = newValue } }
    }

    public var source: ProcessSource {
        ProcessSource { [self] in
            let runner = CommandRunner { [self] executable, arguments, _ in
                precondition(executable == ProcessList.ps && arguments == ProcessList.psArguments)
                return answer()
            }
            let cursor = cursorAppRunning
            let paths = executables
            return await ProcessList.capture(runner: runner, cursorAppRunning: { cursor }, executablePath: { paths[$0] })
        }
    }

    private func answer() -> ProcessResult {
        lock.withLock {
            captures += 1
            return failing
                ? ProcessResult(exitCode: 1, stdout: Data(), stderr: "ps: broken", timedOut: false)
                : ProcessResult(exitCode: 0, stdout: Data(current.utf8), stderr: "", timedOut: false)
        }
    }

    /// One ps line: pid right-aligned in 5, `comm` cut or padded to 16, then the arguments.
    public static func line(pid: Int32, command: String? = nil, arguments: String) -> String {
        let comm = command ?? String(arguments.split(separator: " ").first ?? "")
        let column = comm.count >= 16 ? String(comm.prefix(16)) : comm.padding(toLength: 16, withPad: " ", startingAt: 0)
        let number = String(pid)
        return String(repeating: " ", count: max(0, 5 - number.count)) + number + " " + column + " " + arguments
    }
}
