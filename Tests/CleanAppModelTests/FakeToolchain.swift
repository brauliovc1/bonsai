import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// A scripted docker, xcrun and `defaults`: answers what the scanners ask, records every call, and can change
/// its answers between calls (a daemon that stops, a runtime that goes away). No test ever starts a real
/// docker or xcrun: the binaries are at `/fake/bin`, which doesn't exist.
final class FakeToolchain: @unchecked Sendable {
    static let docker = URL(fileURLWithPath: "/fake/bin/docker")
    static let xcrun = URL(fileURLWithPath: "/fake/bin/xcrun")
    static let defaults = URL(fileURLWithPath: "/fake/bin/defaults")

    /// Images 5.2 GB reclaimable, containers 0, volumes 512 MB reclaimable, build cache 1 GB reclaimable.
    static let dfOutput = """
        {"Active":"3","Reclaimable":"5.2GB (62%)","Size":"8.4GB","TotalCount":"12","Type":"Images"}
        {"Active":"1","Reclaimable":"0B (0%)","Size":"1.2kB","TotalCount":"1","Type":"Containers"}
        {"Active":"2","Reclaimable":"512MB","Size":"3.4GB","TotalCount":"4","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"1GB","Size":"1GB","TotalCount":"7","Type":"Build Cache"}
        """

    static func devices(unavailable: [(udid: String, name: String, bytes: Int)]) -> String {
        let entries = unavailable.map {
            """
            { "dataPathSize" : \($0.bytes), "udid" : "\($0.udid)", "isAvailable" : false, "name" : "\($0.name)", "state" : "Shutdown" }
            """
        }.joined(separator: ",\n")
        return """
            { "devices" : {
              "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
                { "dataPathSize" : 1368854528, "udid" : "AAAA", "isAvailable" : true, "name" : "iPhone 15 Pro", "state" : "Shutdown" }\(entries.isEmpty ? "" : ",")
                \(entries)
              ]
            } }
            """
    }

    static let runtimesJSON = """
        {
          "905CF5D6-411E-4920-956C-1C73C6CD86D2" : {
            "build" : "24A434", "deletable" : true, "kind" : "Patchable Cryptex Disk Image",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "sizeBytes" : 8067000161, "version" : "27.0"
          }
        }
        """

    private struct State {
        var dockerRunning = true
        var daemonOS = "Docker Desktop"
        var unavailable: [(udid: String, name: String, bytes: Int)] = [
            ("BBBB", "iPhone 15", 123_456), ("CCCC", "iPad Air", 200_000),
        ]
        var customDerivedDataLocation: String?
        /// stderr of a failing `docker system df`; nil = it works.
        var dfFailure: String?
        /// stderr of a failing `simctl list devices`; nil = it works.
        var devicesFailure: String?
        /// Runs inside every call, before it is answered (a test can block the call here).
        var onCall: (@Sendable (ScriptedCommandRunner.Call) -> Void)?
    }

    private let lock = NSLock()
    private var state = State()
    private var scripted: ScriptedCommandRunner?

    init() {
        scripted = ScriptedCommandRunner { [unowned self] call in try answer(call) }
    }

    var runner: CommandRunner { scripted!.runner }
    var calls: [ScriptedCommandRunner.Call] { scripted!.calls }

    /// The calls that change something: `docker system prune -f` and `xcrun simctl delete unavailable`.
    var pruneCalls: [ScriptedCommandRunner.Call] { calls.filter { $0.arguments == ["system", "prune", "-f"] } }
    var deleteCalls: [ScriptedCommandRunner.Call] {
        calls.filter { $0.arguments == ["simctl", "delete", "unavailable"] }
    }
    var changingCalls: [ScriptedCommandRunner.Call] { pruneCalls + deleteCalls }

    var dockerRunning: Bool {
        get { lock.withLock { state.dockerRunning } }
        set { lock.withLock { state.dockerRunning = newValue } }
    }

    var daemonOS: String {
        get { lock.withLock { state.daemonOS } }
        set { lock.withLock { state.daemonOS = newValue } }
    }

    var unavailable: [(udid: String, name: String, bytes: Int)] {
        get { lock.withLock { state.unavailable } }
        set { lock.withLock { state.unavailable = newValue } }
    }

    var customDerivedDataLocation: String? {
        get { lock.withLock { state.customDerivedDataLocation } }
        set { lock.withLock { state.customDerivedDataLocation = newValue } }
    }

    var dfFailure: String? {
        get { lock.withLock { state.dfFailure } }
        set { lock.withLock { state.dfFailure = newValue } }
    }

    var devicesFailure: String? {
        get { lock.withLock { state.devicesFailure } }
        set { lock.withLock { state.devicesFailure = newValue } }
    }

    var onCall: (@Sendable (ScriptedCommandRunner.Call) -> Void)? {
        get { lock.withLock { state.onCall } }
        set { lock.withLock { state.onCall = newValue } }
    }

    private func answer(_ call: ScriptedCommandRunner.Call) throws -> ProcessResult {
        let state = lock.withLock { self.state }
        state.onCall?(call)
        switch (call.executable, call.arguments) {
        case (Self.docker, ["info", "--format", "{{.ServerVersion}}"]):
            return state.dockerRunning
                ? ScriptedCommandRunner.result(stdout: "27.0.1\n")
                : ScriptedCommandRunner.result(exitCode: 1, stderr: "Cannot connect to the Docker daemon")
        case (Self.docker, ["info", "--format", "{{.OperatingSystem}}"]):
            return ScriptedCommandRunner.result(stdout: state.daemonOS + "\n")
        case (Self.docker, ["system", "df", "--format", "{{json .}}"]):
            return state.dfFailure.map { ScriptedCommandRunner.result(exitCode: 1, stderr: $0) }
                ?? ScriptedCommandRunner.result(stdout: Self.dfOutput)
        case (Self.docker, ["system", "prune", "-f"]):
            return ScriptedCommandRunner.result(stdout: "Deleted Containers:\nabc123\nTotal reclaimed space: 1.5GB\n")
        case (Self.xcrun, ["simctl", "list", "devices", "-j"]):
            return state.devicesFailure.map { ScriptedCommandRunner.result(exitCode: 1, stderr: $0) }
                ?? ScriptedCommandRunner.result(stdout: Self.devices(unavailable: state.unavailable))
        case (Self.xcrun, ["simctl", "runtime", "list", "-j"]):
            return ScriptedCommandRunner.result(stdout: Self.runtimesJSON)
        case (Self.xcrun, ["simctl", "delete", "unavailable"]):
            return ScriptedCommandRunner.result()
        case (Self.defaults, LiveXcodePreferences.customLocationArguments):
            return state.customDerivedDataLocation.map { ScriptedCommandRunner.result(stdout: $0 + "\n") }
                ?? ScriptedCommandRunner.result(exitCode: 1, stderr: "does not exist")
        default:
            throw ScriptedCommandRunner.StartFailure()
        }
    }
}

extension CleanEnvironment {
    /// The same environment with docker, xcrun and `defaults` pointing at the fake binaries.
    func withFakeTools(docker: Bool = true, xcrun: Bool = true, developerTools: Bool = true) -> CleanEnvironment {
        var copy = self
        copy.tools.docker = docker ? FakeToolchain.docker : nil
        copy.tools.xcrun = xcrun ? FakeToolchain.xcrun : nil
        copy.tools.defaults = FakeToolchain.defaults
        copy.tools.developerToolsInstalled = developerTools
        return copy
    }
}

/// Fake DerivedData folders, in any root inside the temp dir.
enum DerivedDataFixture {
    /// Xcode's default DerivedData folder below `home`.
    static func root(in home: URL) -> URL {
        home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
    }

    /// A folder with `kibibytes` KiB of build output. `workspace` goes into `info.plist` (nil: no plist at
    /// all). Temp folders are under `/var/folders`, which Xcode's classification treats as its own temporary
    /// workspaces, so a workspace that should be orphaned names a path elsewhere that does not exist.
    @discardableResult
    static func entry(in root: URL, _ name: String, workspace: String?, kibibytes: Int = 8) throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Build"), withIntermediateDirectories: true)
        try Data(count: kibibytes * 1024).write(to: folder.appending(path: "Build/blob"))
        if let workspace { try rewritePlist(of: folder, workspace: workspace) }
        return folder
    }

    static func rewritePlist(of folder: URL, workspace: String) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspace], format: .xml, options: 0)
        try plist.write(to: folder.appending(path: "info.plist"))
    }
}

extension FakeHome {
    var derivedDataRoot: URL { DerivedDataFixture.root(in: url) }

    @discardableResult
    func derivedDataEntry(_ name: String, workspace: String?, kibibytes: Int = 8) throws -> URL {
        try DerivedDataFixture.entry(in: derivedDataRoot, name, workspace: workspace, kibibytes: kibibytes)
    }

    func rewritePlist(of folder: URL, workspace: String) throws {
        try DerivedDataFixture.rewritePlist(of: folder, workspace: workspace)
    }
}

/// A workspace path that does not exist and is not under `/var/folders` or `/Volumes`: its DerivedData
/// folder is orphaned.
func goneWorkspace(_ name: String) -> String {
    "/Users/bonsai-no-such-user/\(name)/\(name).xcodeproj"
}

/// Holds one call of the fake toolchain until the test lets it go: `toolchain.onCall = gate.hold { … }`
/// blocks the matching call on its own thread, `waitUntilReached` waits for it without blocking the main
/// actor, and `release` lets it answer.
final class CallGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reachedFlag = false
    private let released = DispatchSemaphore(value: 0)

    var isReached: Bool { lock.withLock { reachedFlag } }

    func hold(when matches: @escaping @Sendable (ScriptedCommandRunner.Call) -> Bool) -> @Sendable (ScriptedCommandRunner.Call) -> Void {
        { [self] call in
            guard matches(call) else { return }
            lock.withLock { reachedFlag = true }
            released.wait()
        }
    }

    func waitUntilReached() async throws {
        for _ in 0..<2_000 where !isReached {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(isReached, "the held call was never made")
    }

    func release() {
        released.signal()
    }
}
