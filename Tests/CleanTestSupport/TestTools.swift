import CleanCore
import Foundation

/// The tools the test helpers and the code under test run, resolved once: `ToolPaths.resolve()`, except that git
/// is the real binary `xcrun --find git` names instead of `/usr/bin/git`.
///
/// `/usr/bin/git` and `/usr/bin/make` are xcrun shims. When xcrun's lookup cache misses, which it does on a cold
/// machine and for every new `SDKROOT` (`swift test` sets one), each call runs `xcodebuild -find` first, and that
/// takes seconds. With hundreds of fixtures starting at once on a 3-core runner, git calls took over a minute (CI
/// run 42770493700). Running `xcrun --find git` here, with this process's environment, also fills that cache for
/// the shims the `bonsai` binary runs in the CLI tests. Tests of the production tool lookup call
/// `ToolPaths.resolve()` themselves.
public enum TestTools {
    public static let paths: ToolPaths = {
        var tools = ToolPaths.resolve()
        if let xcrun = tools.xcrun, let git = find("git", xcrun: xcrun) { tools.git = git }
        return tools
    }()

    /// The real `make`, for the Makefile tests; `/usr/bin/make` when xcrun can't name it.
    public static let make: URL = paths.xcrun.flatMap { find("make", xcrun: $0) } ?? URL(fileURLWithPath: "/usr/bin/make")

    /// `xcrun --find <tool>`: the path it prints, when it exits 0 within `TestWait.limit` and names an executable.
    /// `xcrun` is only in `paths` when `xcode-select -p` succeeds, so this never opens the Command Line Tools installer.
    static func find(_ tool: String, xcrun: URL) -> URL? {
        let process = Process()
        process.executableURL = xcrun
        process.arguments = ["--find", tool]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // One short line, far below the pipe buffer: it is read once xcrun has ended.
        guard ended.wait(timeout: TestWait.deadline) == .success else {
            process.terminate()
            return nil
        }
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
