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

    /// The real ps is run by absolute path with the fixed arguments; a failure is a failure, not an empty list.
    @Test func captureRunsPsAndReportsFailures() async throws {
        let scripted = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: Self.output) }
        let list = await ProcessList.capture(runner: scripted.runner)
        #expect(scripted.calls.map(\.executable) == [URL(fileURLWithPath: "/bin/ps")])
        #expect(scripted.calls.first?.arguments == ["-axo", "pid=,comm=,args="])
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
