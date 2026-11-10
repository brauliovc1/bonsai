@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func set(_ date: Date) {
        lock.withLock { current = date }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Records what auto mode asks of notifications.
@MainActor
final class RecordingNotifier: Notifier {
    var authorizationRequests = 0
    var posted: [NotificationContent] = []
    /// False: notifications aren't allowed, `post` shows nothing and says so.
    var allowed = true
    /// Runs inside `post`, after recording (a test can start something while a run is finishing).
    var onPost: (@MainActor () async -> Void)?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return allowed
    }

    func post(_ content: NotificationContent) async -> Bool {
        guard allowed else { return false }
        posted.append(content)
        await onPost?()
        return true
    }
}

/// The demo world plus `atlas-edge`, clean and pushed, 29 days idle (one day short of the threshold), with
/// a fake clock at the moment the ages count back from, a recording notifier, and the screen models.
@MainActor
struct AutoWorld {
    let demo: DemoWorld
    let clock: TestClock
    let notifier: RecordingNotifier
    let models: ScreenModels

    var app: AppModel { models.app }
    var autoMode: AutoModeModel { models.autoMode }
    var environment: CleanEnvironment { app.environment }

    /// `enabledDaysAgo`: auto mode was turned on this many days before the clock (nil: off). 1 = inside the
    /// report-only week, 8 = after it. `startDateMissing`: on, but with no `autoEnabledAt`. `gate`: git's
    /// `worktree remove` and lsof stop at the gate when it is armed.
    static func make(
        enabledDaysAgo: Int?,
        includeClaude: Bool = false,
        startDateMissing: Bool = false,
        gate: ProcessGate? = nil
    ) async throws -> AutoWorld {
        // Whole seconds: settings.json keeps dates to the second.
        let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let demo = try await DemoWorld.build(now: start)
        try await agedSibling(of: demo.fixture.scanRoot.appending(path: "atlas"), "edge", in: demo.fixture, days: 29, now: start)

        let clock = TestClock(start)
        var environment = demo.fixture.environment(scanRoots: [demo.folder]).withFakeTools()
        environment.now = { clock.now }
        var settings = Settings(includeClaudeInAuto: includeClaude)
        if let days = enabledDaysAgo {
            settings.autoEnabled = true
            settings.autoEnabledAt = startDateMissing ? nil : start.addingTimeInterval(-TimeInterval(days) * 86_400)
        }
        try SettingsStore(environment: environment).save(settings)

        var git = demo.fixture.git
        if let gate {
            try gate.install(in: demo.fixture.url, realGit: git.executable)
            git.executable = gate.git
            git.timeout = TestWait.limit
            environment.tools.lsof = gate.lsof
        }
        let notifier = RecordingNotifier()
        let app = AppModel(environment: environment, git: git)
        let models = ScreenModels(app: app, runner: FakeToolchain().runner, notifier: notifier)
        return AutoWorld(demo: demo, clock: clock, notifier: notifier, models: models)
    }

    func remove() {
        demo.remove()
    }

    func url(_ name: String) throws -> URL {
        if name == "atlas-edge" { return demo.fixture.scanRoot.appending(path: name, directoryHint: .isDirectory) }
        return try demo.url(name)
    }

    func exists(_ name: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try url(name).path)
    }

    func saved() throws -> Settings {
        try SettingsStore(environment: environment).load()
    }

    func logEntries() throws -> [RemovalLogEntry] {
        try RemovalLog(environment: environment).entries()
    }

    /// Folder names of the worktrees the log says were removed.
    func removedNames() throws -> [String] {
        try logEntries().map { URL(fileURLWithPath: $0.path).lastPathComponent }
    }

    func branchExists(_ branch: String) async -> Bool {
        let atlas = demo.fixture.scanRoot.appending(path: "atlas")
        return (try? await demo.fixture.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: atlas)) != nil
    }

    /// A clean sibling `<repo>-<name>` with one pushed commit, every date `days` (and an hour) before `now`,
    /// so the idle clock reads `days` for the next 23 hours.
    private static func agedSibling(of repo: URL, _ name: String, in fixture: GitFixture, days: Int, now: Date) async throws {
        let date = now.addingTimeInterval(-(TimeInterval(days) * 86_400 + 3_600))
        var git = fixture.git
        let stamp = "\(Int(date.timeIntervalSince1970)) +0000"
        git.environmentAdditions["GIT_AUTHOR_DATE"] = stamp
        git.environmentAdditions["GIT_COMMITTER_DATE"] = stamp
        let path = repo.deletingLastPathComponent().appending(path: "\(repo.lastPathComponent)-\(name)", directoryHint: .isDirectory)
        try await git.git(["worktree", "add", "--quiet", "-b", name, path.path], in: repo)
        try fixture.write("\(name)\n", to: "notes/\(name).md", in: path)
        try await git.git(["add", "-A"], in: path)
        try await git.git(["commit", "--quiet", "-m", "Add \(name)"], in: path)
        try await git.git(["push", "--quiet", "-u", "origin", name], in: path)
        try fixture.setModificationDate(date, of: path, recursively: true)
        let gitDir = URL(fileURLWithPath: try await fixture.run(["rev-parse", "--absolute-git-dir"], in: path))
        for file in ["index", "HEAD"] {
            try fixture.setModificationDate(date, of: gitDir.appending(path: file))
        }
    }
}

/// Stand-ins for git and lsof that stop at a gate while it is armed, so a test can act at an exact moment:
/// `stage` "lsof" stops the process-index capture (after `Remover`'s git and disk re-check), "remove" stops
/// `git worktree remove` itself. Arming is one-shot; `open()` lets the stopped call go on.
///
/// No timeout can end the wait: the gated git runs under the world's git timeout (`TestWait.limit`), and the gated
/// lsof waits in a background job after the stand-in itself has exited, so lsof's 30 s don't count while
/// `ProcessRunner` reads the pipes the job still holds. A gate nobody opens gives up once the fixture is gone or
/// after at least `TestWait.limit`.
@MainActor
final class ProcessGate {
    let stage: String
    private(set) var folder = URL(fileURLWithPath: "/nonexistent")

    init(stage: String) {
        self.stage = stage
    }

    var git: URL { folder.appending(path: "git") }
    var lsof: URL { folder.appending(path: "lsof") }
    private var armedFile: URL { folder.appending(path: "armed") }
    private var waitingFile: URL { folder.appending(path: "waiting") }
    private var goFile: URL { folder.appending(path: "go") }

    func install(in fixture: URL, realGit: URL) throws {
        folder = fixture.appending(path: "gate", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let take = "rm -f \"$G/armed\"; touch \"$G/waiting\""
        let wait = """
            n=0; while [ -d "$G" ] && [ ! -e "$G/go" ] && [ $n -lt \(Int(TestWait.seconds / 0.02)) ]; do sleep 0.02; n=$((n + 1)); done
            [ -e "$G/go" ] || { echo "the gate in $G was not opened" >&2; exit 1; }
            """
        let lsofScript = "#!/bin/sh\nG=\"$(dirname \"$0\")\"\n"
            + (stage == "lsof" ? "if [ -e \"$G/armed\" ]; then \(take); (\n\(wait)\nexec /usr/sbin/lsof \"$@\"\n) & exit 0; fi\n" : "")
            + "exec /usr/sbin/lsof \"$@\"\n"
        let gitScript = "#!/bin/sh\nG=\"$(dirname \"$0\")\"\n"
            + (stage == "remove" ? "case \" $* \" in *\" worktree remove \"*) if [ -e \"$G/armed\" ]; then \(take)\n\(wait)\nfi ;; esac\n" : "")
            + "exec \"\(realGit.path)\" \"$@\"\n"
        for (url, text) in [(lsof, lsofScript), (git, gitScript)] {
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    func arm() {
        FileManager.default.createFile(atPath: armedFile.path, contents: nil)
    }

    /// True once a call is stopped at the gate.
    var isWaiting: Bool { FileManager.default.fileExists(atPath: waitingFile.path) }

    func open() {
        FileManager.default.createFile(atPath: goFile.path, contents: nil)
    }
}

/// Waits (yielding) until `condition` holds, for at most `TestWait.limit`.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: TestWait.limit)
    while clock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
