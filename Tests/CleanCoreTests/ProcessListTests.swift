@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches: the process list")
struct ProcessListTests {
    /// Real-looking `ps -axo pid=,comm=,args=` output: `comm` padded or cut to 16 characters, paths with spaces,
    /// node scripts, a Java Gradle daemon, npm's own title, a login shell, a name with non-ASCII characters.
    static let output = """
            1 /sbin/launchd    /sbin/launchd
          884 /System/Library/ /System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService
         1204 -zsh             -zsh
        12069 /opt/homebrew/Ce /opt/homebrew/Cellar/node/24.2.0/bin/node /Users/me/Nexus/backend/node_modules/jest/bin/jest.js --ci --runInBand
        29895 npm exec jest sr npm exec jest src/app.module.boot.spec.ts --testTimeout=120000
        58610 /Applications/Cl /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility --lang=en-US
        61000 java             /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java -Xmx2g -cp /Users/me/.gradle/wrapper/dists/gradle-8.5-bin/lib/gradle-launcher-8.5.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.5
        61200 node             node /opt/homebrew/bin/npm install --global yarn
        61300 /opt/homebrew/op /opt/homebrew/opt/python@3.12/bin/python3.12 -m pip install requests
        61400 /usr/bin/ruby    /usr/bin/ruby -W1 --disable=gems,rubyopt /opt/homebrew/Library/Homebrew/brew.rb upgrade
        61500 env              env NODE_OPTIONS=--max-old-space-size=4096 node ./node_modules/.bin/playwright test
        57541 Ünï he Ünï helper -e sleep 20 /Users/José/x y
        """

    @Test func linesAreSplitIntoPidCommandAndArguments() {
        let processes = ProcessList.parse(Self.output)
        #expect(processes.count == 12)
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        #expect(byPID[1]?.command == "/sbin/launchd")
        #expect(byPID[1]?.arguments == "/sbin/launchd")
        #expect(byPID[884]?.command == "/System/Library/", "comm is cut to 16 characters")
        #expect(byPID[884]?.arguments.hasSuffix("/CursorUIViewService") == true)
        #expect(byPID[58610]?.arguments == "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility --lang=en-US")
        #expect(byPID[29895]?.command == "npm exec jest sr")
        #expect(byPID[61000]?.command == "java")
        // A comm with non-ASCII characters doesn't fit the column: everything after the pid is the command line.
        #expect(byPID[57541]?.command == "")
        #expect(byPID[57541]?.arguments.contains("/Users/José/x y") == true)
    }

    @Test func commandNamesSeeThroughInterpretersAndTitles() {
        let byPID = Dictionary(uniqueKeysWithValues: ProcessList.parse(Self.output).map { ($0.pid, $0.commandNames) })
        #expect(byPID[1] == ["launchd"])
        #expect(byPID[1204]?.contains("zsh") == true, "a login shell's -zsh")
        #expect(byPID[12069]?.isSuperset(of: ["node", "jest.js"]) == true)
        #expect(byPID[12069]?.contains("ce") == false, "a cut comm is not a name")
        #expect(byPID[29895]?.contains("npm") == true, "npm's own title")
        #expect(byPID[58610]?.contains("claude") == true)
        #expect(byPID[61200]?.contains("npm") == true, "node running npm's script")
        #expect(byPID[61300]?.isSuperset(of: ["python3.12", "python3", "python", "pip"]) == true, "python -m pip")
        #expect(byPID[61400]?.contains("brew.rb") == true, "ruby's options are skipped")
        #expect(byPID[61500]?.isSuperset(of: ["env", "node", "playwright"]) == true, "env NAME=value node script")
        #expect(byPID[61000] == ["java"])
    }

    @Test func ownersMatchAsTheTableSays() {
        let list = ProcessList(processes: ProcessList.parse(Self.output))
        func running(_ id: String) -> [String]? {
            list.runningOwners(ToolCacheCatalog.entry(id: id)!.owners, mentioning: [])
        }
        #expect(running("npm") == ["npm"])
        #expect(running("gradle") == ["Gradle"])
        #expect(running("pip") == ["pip"])
        #expect(running("homebrew") == ["brew"])
        #expect(running("playwright") == ["Playwright"])
        #expect(running("yarn") == [], "\"yarn\" as an argument of npm isn't Yarn running")
        #expect(running("go-build") == [])
        #expect(running("cursor-caches") == [], "CursorUIViewService is not Cursor")
        #expect(!list.isCursorRunning)
        #expect(running("swiftpm") == [])
    }

    /// A process whose command line names a target counts as using it; `du` (the scanner's own) doesn't.
    @Test func aProcessRunningFromACacheIsAnOwner() {
        let cache = "/Users/me/Library/Caches/ms-playwright"
        let list = ProcessList(processes: [
            ProcessList.Process(pid: 70, command: "/Users/me/Libra", arguments: cache + "/chromium-1140/chrome-mac/Chromium.app/Contents/MacOS/Chromium --headless"),
            ProcessList.Process(pid: 71, command: "/usr/bin/du", arguments: "/usr/bin/du -skx " + cache),
        ])
        #expect(list.runningOwners([], mentioning: [cache]) == ["Chromium"])
        #expect(list.runningOwners([], mentioning: ["/Users/me/.npm/_cacache"]) == [])
        #expect(ProcessList(processes: [], failure: "ps timed out").runningOwners([], mentioning: [cache]) == nil)
    }

    /// bonsai's own command line names entries (`caches clean playwright cursor-agent-versions`), also under its old
    /// name clean-claude (the link `make install` leaves) and under sudo: it never counts as an owner. This process
    /// neither.
    @Test func bonsaiItselfIsNeverAnOwner() {
        let list = ProcessList(processes: [
            ProcessList.Process(pid: 79, command: "bonsai", arguments: "/Users/me/.local/bin/bonsai caches clean playwright cursor-agent-versions --yes"),
            ProcessList.Process(pid: 80, command: "clean-claude", arguments: "/Users/me/.local/bin/clean-claude caches clean playwright cursor-agent-versions --yes"),
            ProcessList.Process(pid: 81, command: "sudo", arguments: "sudo clean-claude caches clean playwright --yes"),
            ProcessList.Process(pid: getpid(), command: "node", arguments: "node /x/npm-cli.js playwright"),
        ])
        for id in ["playwright", "cursor-agent-versions", "npm"] {
            #expect(list.runningOwners(ToolCacheCatalog.entry(id: id)!.owners, mentioning: []) == [], "\(id)")
        }
        let other = ProcessList(processes: [ProcessList.Process(pid: 82, command: "node", arguments: "node /x/npm-cli.js playwright")])
        #expect(other.runningOwners(ToolCacheCatalog.entry(id: "playwright")!.owners, mentioning: []) == ["Playwright"])
    }

    /// Review item 4, probe `probeConcurrentDuCountsAsOwner`: du, ps and Bonsai's own processes never count as
    /// owners under any rule, also the argument-text rules (`du -skx …/ms-playwright`, `…/cursor-agent/versions/<v>`).
    @Test func duPsAndBonsaiAreNeverOwners() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.run(
            "/usr/bin/du -skx " + world.path("Library/Caches/ms-playwright"),
            "/usr/bin/du -skx " + world.path(ToolCacheWorld.versions + "/" + ToolCacheWorld.oldVersions[0]),
            "/bin/ps -axo pid=,comm=,args= playwright GradleDaemon",
            "/Applications/Bonsai.app/Contents/MacOS/Bonsai playwright /x/cursor-agent/versions/y",
            "/Users/me/bonsai/.build/debug/CleanClaudeApp mongodb-memory-server"
        )
        let report = await world.scanner().scan()
        for id in ["playwright", "cursor-agent-versions", "gradle", "mongodb-binaries", "npm"] {
            let finding = try report.require(id)
            #expect(finding.isReady, "\(id): \(finding.verdict)")
        }
        // The same command lines from any other program do count.
        world.processes.run("/usr/local/bin/watch " + world.path("Library/Caches/ms-playwright"))
        #expect(try await world.scanner().scan().require("playwright").verdict == .refused("Quit Playwright and watch to clean this"))
    }

    /// Review item 2: a tool under a folder with spaces or accents can't be split back out of `args`; its executable
    /// path (`proc_pidpath`) names it. Canned: the kernel's path for each pid.
    @Test func theExecutablePathNamesAToolUnderAPathWithSpaces() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let tools = [
            (3000, "/Users/me/A B C/bin/npm", "install", "npm", "Quit npm to clean this"),
            (3001, "/Users/me/My Flutter SDK/bin/cache/dart-sdk/bin/dart", "pub get", "pub", "Quit dart to clean this"),
            (3002, "/Users/me/Dévelöppé Tools/bin/pod", "install", "cocoapods", "Quit pod to clean this"),
        ]
        for (pid, path, arguments, id, sentence) in tools {
            world.processes.output = ScriptedProcesses.idle + "\n" + ScriptedProcesses.line(pid: Int32(pid), arguments: path + " " + arguments)
            world.processes.executables = [:]
            #expect(try await world.scanner().scan().require(id).isReady, "\(id): args alone don't name it")
            world.processes.executables = [Int32(pid): path]
            #expect(try await world.scanner().scan().require(id).verdict == .refused(sentence), "\(id)")
        }
    }

    /// Review item 2 with the real `/bin/ps` and `proc_pidpath` (probe `probeRealPsOwnerDetection`): copies of
    /// `/bin/cat` started from folders with spaces and accents, named like the tools, are seen as their owners. They
    /// run until the test stops them, and ps may take as long as the machine needs (a scan gives it 20 s).
    @Test func realProcessesUnderAwkwardPathsAreSeen() async throws {
        let folder = try TemporaryDirectory(prefix: "bonsai-procs")
        defer { folder.remove() }
        let launches = [
            ("A B C/bin/npm", "npm", "npm"),
            ("My Flutter SDK/bin/cache/dart-sdk/bin/dart", "pub", "dart"),
            ("Dévelöppé Tools/bin/pod", "cocoapods", "pod"),
        ]
        var started: [SleepingProcess] = []
        defer { started.forEach { $0.stop() } }
        for (path, _, _) in launches {
            let url = folder.url.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/cat"), to: url)
            // A copy of a system binary keeps Apple's signature and is killed at launch; an ad-hoc signature runs.
            let signed = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", url.path],
                timeout: TestWait.limit
            )
            #expect(signed.succeeded, "codesign \(path): \(signed.timedOut ? "didn't finish within \(TestWait.limit)" : signed.stderr)")
            let process = SleepingProcess(executable: url)
            try process.start(in: folder.url)
            started.append(process)
        }
        let live = await ProcessList.capture(runner: CommandRunner { executable, arguments, _ in
            try await ProcessRunner.run(executable: executable, arguments: arguments, timeout: TestWait.limit)
        })
        #expect(live.failure == nil)
        for ((path, id, owner), process) in zip(launches, started) {
            let pid = try #require(process.pid)
            let line = try #require(live.processes.first { $0.pid == pid }, "\(path) is in ps")
            #expect(line.executable.map(CanonicalPath.resolve) == CanonicalPath.resolve(folder.url.appending(path: path)),
                    "pid \(line.pid) comm [\(line.command)] args [\(line.arguments)] executable \(line.executable ?? "nil")")
            let single = ProcessList(processes: [line])
            #expect(single.runningOwners(ToolCacheCatalog.entry(id: id)!.owners, mentioning: []) == [owner], "\(path)")
        }
    }

    /// The real ps is run by absolute path with the fixed arguments; a failure is a failure, not an empty list.
    @Test func captureRunsPsAndReportsFailures() async throws {
        let scripted = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: Self.output) }
        let list = await ProcessList.capture(runner: scripted.runner)
        #expect(scripted.calls.map(\.executable) == [URL(fileURLWithPath: "/bin/ps")])
        #expect(scripted.calls.first?.arguments == ["-axo", "pid=,comm=,args="])
        #expect(scripted.calls.first?.timeout == .seconds(20))
        #expect(list.processes.count == 12 && list.failure == nil)

        let empty = await ProcessList.capture(runner: ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }.runner)
        #expect(empty.failure == "ps listed no processes")
        let timedOut = await ProcessList.capture(runner: ScriptedCommandRunner { _ in ScriptedCommandRunner.result(timedOut: true) }.runner)
        #expect(timedOut.failure == "ps timed out")
        let missing = await ProcessList.capture(runner: ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }.runner)
        #expect(missing.failure?.hasPrefix("ps could not be started") == true)
    }

    /// The idle output the other tests use parses back as written.
    @Test func theScriptedLinesParse() {
        let line = ScriptedProcesses.line(pid: 3, arguments: "/opt/homebrew/Cellar/node/24.2.0/bin/node /x/npm-cli.js")
        #expect(line.hasPrefix("    3 /opt/homebrew/Ce /opt/"))
        #expect(ProcessList.parse(ScriptedProcesses.idle).count == 6)
        #expect(ProcessList.parse(line).first?.arguments == "/opt/homebrew/Cellar/node/24.2.0/bin/node /x/npm-cli.js")
    }
}
