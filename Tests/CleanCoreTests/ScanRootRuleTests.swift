@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Scan roots in settings")
struct ScanRootRuleTests {
    private func refusal(_ rule: ScanRootRule, _ path: String) -> String? {
        if case .failure(let refusal) = rule.accept(URL(fileURLWithPath: path)) { refusal.reason } else { nil }
    }

    /// Only a folder strictly inside home or strictly inside /Volumes/<name>/ is a scan root.
    @Test func onlyFoldersInsideHomeOrAVolumeAreAccepted() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let home = folder.url.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "code/app"), withIntermediateDirectories: true)
        let rule = ScanRootRule(home: home)
        let canonicalHome = CanonicalPath.resolve(home)

        #expect(try rule.accept(home.appending(path: "code")).get().path == canonicalHome + "/code")
        #expect(try rule.accept(home.appending(path: "code/app")).get().path == canonicalHome + "/code/app")
        #expect(try rule.accept(home.appending(path: "not-created-yet")).get().path == canonicalHome + "/not-created-yet")
        #expect(try rule.accept(URL(fileURLWithPath: "/Volumes/Work/code")).get().path == "/Volumes/Work/code")

        #expect(refusal(rule, "/")?.contains("whole disk") == true)
        #expect(refusal(rule, home.path)?.contains("home folder itself") == true)
        #expect(refusal(rule, home.deletingLastPathComponent().path)?.contains("contains the home folder") == true)
        #expect(refusal(rule, "/Volumes")?.contains("volume's root") == true)
        #expect(refusal(rule, "/Volumes/Work")?.contains("volume's root") == true)
        for system in ["/opt", "/opt/homebrew", "/usr", "/usr/local", "/Library", "/System", "/Applications", "/etc", "/Users"] {
            #expect(refusal(rule, system)?.contains("outside the home folder") == true, "\(system)")
        }
        #expect(refusal(rule, "/private") != nil, "/private holds the temp home here, so it is an ancestor of it")
    }

    @Test func symlinksAreResolvedBeforeTheRuleApplies() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let home = folder.url.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "code"), withIntermediateDirectories: true)
        let rule = ScanRootRule(home: home)
        let inside = home.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: inside, withDestinationURL: home.appending(path: "code"))
        let toOpt = home.appending(path: "to-opt")
        try FileManager.default.createSymbolicLink(at: toOpt, withDestinationURL: URL(fileURLWithPath: "/opt"))
        let toRoot = home.appending(path: "to-root")
        try FileManager.default.createSymbolicLink(at: toRoot, withDestinationURL: URL(fileURLWithPath: "/"))
        let toHome = home.appending(path: "to-home")
        try FileManager.default.createSymbolicLink(at: toHome, withDestinationURL: home)

        #expect(try rule.accept(inside).get().path == CanonicalPath.resolve(home) + "/code", "stored canonical")
        for link in [toOpt, toRoot, toHome] {
            let reason = refusal(rule, link.path)
            #expect(reason?.contains("leads to") == true, "\(link.lastPathComponent): \(reason ?? "accepted")")
        }
        // The macOS startup disk's alias to "/" is refused for what it leads to.
        #expect(refusal(rule, "/Volumes/Macintosh HD") == nil || refusal(rule, "/Volumes/Macintosh HD")?.contains("whole disk") == true)
    }

    @Test func aSettingsFileWithSuchRootsReportsThemAndSkipsThem() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let code = fixture.home.appending(path: "code", directoryHint: .isDirectory)
        try await fixture.makeRepo("solo", in: code)
        let alias = fixture.home.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: code)
        let settings = Settings(scanRoots: ["/", "~", "/opt", "~/code", alias.path])
        let environment = fixture.environment()

        let roots = settings.scanRootURLs(home: environment.homeDirectory)
        #expect(roots.map(\.path) == [CanonicalPath.resolve(code)], "symlink resolved, and listed once")
        let homePath = environment.homeDirectory.path
        let refused = settings.refusedScanRoots(home: environment.homeDirectory)
        #expect(refused.map(\.path) == ["/", homePath, "/opt"])
        #expect(Scanner.resolveRoots(explicit: [], environment: environment, settings: settings).map(\.path) == roots.map(\.path))

        let scan = await Scanner(environment: environment, settings: settings).scan()
        let issues = scan.issues.filter { $0.kind == .rootRefused }
        #expect(issues.map(\.path) == ["/", homePath, "/opt"], "\(scan.issues)")
        #expect(issues.allSatisfy { $0.message.hasPrefix("scan root skipped: ") })
        #expect(scan.repos.map { URL(fileURLWithPath: $0).lastPathComponent } == ["solo"], "the accepted root was scanned")
        #expect(!scan.roots.contains("/") && !scan.roots.contains("/opt"))
    }

    /// An explicit root (CLI `--root`, the environment variable) is the person's choice for one run.
    @Test func explicitRootsAreNotJudged() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let settings = Settings(scanRoots: ["/opt"])
        let explicit = Scanner.resolveRoots(explicit: [fixture.scanRoot], environment: fixture.environment(), settings: settings)
        #expect(explicit == [fixture.scanRoot])
        let override = Scanner.resolveRoots(explicit: [], environment: fixture.environment(scanRoots: [fixture.scanRoot]), settings: settings)
        #expect(override == [fixture.scanRoot])

        let scan = await Scanner(environment: fixture.environment(scanRoots: [fixture.scanRoot]), settings: settings).scan()
        #expect(scan.issues.filter { $0.kind == .rootRefused }.isEmpty, "the saved list isn't what decides here")
        let viaFlag = await Scanner(environment: fixture.environment(), settings: settings).scan(roots: [fixture.scanRoot])
        #expect(viaFlag.issues.filter { $0.kind == .rootRefused }.isEmpty)
    }

    /// /opt/homebrew is a git checkout whose "/*" rule ignores lib/node_modules: as a saved root it must
    /// never reach light clean.
    @Test func aHomebrewLikeRootSavedInSettingsIsNeverScanned() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let outside = fixture.scanRoot // a sibling of home, like /opt next to /Users
        let brew = try await fixture.makeRepo("homebrew", in: outside)
        try fixture.write("/*\n!.gitignore\n", to: ".gitignore", in: brew)
        try fixture.write("x\n", to: "lib/node_modules/pkg/index.js", in: brew)
        let settings = Settings(scanRoots: [outside.path])

        let scan = await Scanner(environment: fixture.environment(), settings: settings).scan()

        #expect(scan.repos.isEmpty, "\(scan.repos)")
        #expect(scan.worktrees.isEmpty)
        #expect(scan.issues.contains { $0.kind == .rootRefused && $0.path == outside.standardizedFileURL.path })
    }
}
