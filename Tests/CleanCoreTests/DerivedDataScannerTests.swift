@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.4: where DerivedData is and which of its folders are orphaned.
@Suite("DerivedData scanning")
struct DerivedDataScannerTests {
    /// With the real /var/folders rule, so project paths can't live in the fixture: an orphan's project is a
    /// path that can't exist, a live one a system folder that always does.
    @Test func everyStateFollowsPlan44() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        let gonePath = "/nonexistent-clean-claude-\(UUID().uuidString)/Gone.xcworkspace"
        try world.entry("Gone-aaa", workspace: gonePath, kibibytes: 12)
        try world.entry("Live-bbb", workspace: "/usr/bin")
        try world.entry("Files-ccc", workspace: "/private/var/folders/l0/x/C/com.apple.DeveloperTools/Files.xcfilescontainer")
        try world.entry("Temp-ddd", workspace: "/var/folders/l0/x/T/Playground.playground")
        try world.folder("ModuleCache.noindex")
        try world.entry("Broken-eee", rawPlist: "this is {not a plist")
        try world.entry("NoKey-fff", plist: ["LastAccessedDate": Date()])
        try world.entry("Relative-ggg", workspace: "Relative.xcodeproj")
        // Not entries: a file and a symlink in the root.
        try Data("x".utf8).write(to: world.root.appending(path: ".DS_Store"))
        try FileManager.default.createSymbolicLink(at: world.root.appending(path: "Link-hhh"), withDestinationURL: world.projects)

        let report = await world.scanner(internalPrefixes: DerivedDataClassifier.xcodeInternalPrefixes).scan()

        #expect(report.rootExists && report.warnings.isEmpty, "\(report.warnings)")
        let states = Dictionary(uniqueKeysWithValues: report.entries.map { ($0.name, $0.state) })
        #expect(states == [
            "Broken-eee": .unreadable, "Files-ccc": .xcodeInternal, "Gone-aaa": .orphaned, "Live-bbb": .live,
            "ModuleCache.noindex": .noInfoPlist, "NoKey-fff": .unreadable, "Relative-ggg": .unreadable,
            "Temp-ddd": .xcodeInternal,
        ])
        #expect(report.entries.map(\.name) == report.entries.map(\.name).sorted())
        #expect(report.orphans.map(\.name) == ["Gone-aaa"])
        #expect(report.entries.filter { $0.state != .orphaned }.allSatisfy { $0.orphan == nil })

        let gone = try #require(report.entries.first { $0.name == "Gone-aaa" })
        #expect(gone.workspacePath == gonePath && gone.orphan?.workspacePath == gonePath)
        // 12 KiB of build output plus info.plist's one block.
        #expect(gone.bytes == Int64(16 * 1024) && gone.orphan?.bytes == Int64(16 * 1024))
        #expect(gone.orphan?.folder == world.root.path + "/Gone-aaa")
        #expect(report.entries.first { $0.name == "Broken-eee" }?.detail == "info.plist is not a property list dictionary")
        #expect(report.entries.first { $0.name == "NoKey-fff" }?.detail == "info.plist has no WorkspacePath")
        #expect(report.entries.first { $0.name == "Relative-ggg" }?.detail == "WorkspacePath is not an absolute path")
        #expect(report.bytes(in: .orphaned) == Int64(16 * 1024))
    }

    @Test func aProjectPathThatCannotBeCheckedIsUnreadableNotOrphaned() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        let locked = world.projects.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked.appending(path: "App.xcodeproj"), withIntermediateDirectories: true)
        try world.entry("App-aaa", workspace: CanonicalPath.resolve(locked) + "/App.xcodeproj")
        try world.entry("Gone-bbb", workspace: CanonicalPath.resolve(locked) + "/Gone.xcodeproj")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let report = await world.scanner().scan()

        #expect(report.entries.map(\.state) == [.unreadable, .unreadable])
        #expect(report.orphans.isEmpty)
        #expect(report.entries.allSatisfy { $0.detail?.hasPrefix("the project path can't be checked") == true })
    }

    @Test func aMissingRootIsReportedNotAnError() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try FileManager.default.removeItem(at: world.root)

        let report = await world.scanner().scan()
        #expect(!report.rootExists && report.entries.isEmpty && report.warnings.isEmpty)
    }

    @Test func theLocatorUsesXcodesCustomLocationOrTheDefault() async throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let standard = DerivedDataLocator(preferences: FakeXcodePreferences(value: nil), homeDirectory: home)
        let located = await standard.locate()
        #expect(located.root.path == "/Users/someone/Library/Developer/Xcode/DerivedData")
        #expect(!located.isCustom && located.note == nil)

        let tilde = await DerivedDataLocator(preferences: FakeXcodePreferences(value: "~/Builds/DD"), homeDirectory: home).locate()
        #expect(tilde.root.path == "/Users/someone/Builds/DD" && tilde.isCustom && tilde.note == nil)

        let absolute = await DerivedDataLocator(preferences: FakeXcodePreferences(value: "/Volumes/Fast/DD"), homeDirectory: home).locate()
        #expect(absolute.root.path == "/Volumes/Fast/DD" && absolute.isCustom)

        let relative = await DerivedDataLocator(preferences: FakeXcodePreferences(value: "DerivedData"), homeDirectory: home).locate()
        #expect(relative.root.path == standard.defaultRoot.path && !relative.isCustom)
        #expect(relative.note?.contains("relative") == true)
    }

    @Test func theScannerListsTheCustomLocation() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("Gone-aaa", workspace: "/nonexistent-clean-claude-\(UUID().uuidString)/Gone.xcodeproj")
        let location = await DerivedDataLocator(preferences: FakeXcodePreferences(value: world.root.path), homeDirectory: world.directory.url).locate()

        let report = await DerivedDataScanner(root: location.root, du: nil, homeDirectory: world.home).scan()
        #expect(report.root == world.root.path)
        #expect(report.orphans.map(\.name) == ["Gone-aaa"])
        #expect(report.entries.allSatisfy { $0.bytes == nil }, "no du, no sizes")
    }

    @Test func liveXcodePreferencesReadsTheKeyWithDefaults() async {
        let defaults = URL(fileURLWithPath: "/fake/bin/defaults")
        let set = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "/Volumes/Fast/DD\n") }
        #expect(await LiveXcodePreferences(defaults: defaults, runner: set.runner).customDerivedDataLocation() == "/Volumes/Fast/DD")
        #expect(set.calls.map(\.executable) == [defaults])
        #expect(set.calls.map(\.arguments) == [["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"]])

        let unset = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(exitCode: 1, stderr: "The domain/default pair of (com.apple.dt.Xcode, IDECustomDerivedDataLocation) does not exist")
        }
        #expect(await LiveXcodePreferences(defaults: defaults, runner: unset.runner).customDerivedDataLocation() == nil)

        let empty = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "\n") }
        #expect(await LiveXcodePreferences(defaults: defaults, runner: empty.runner).customDerivedDataLocation() == nil)

        let missing = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        #expect(await LiveXcodePreferences(defaults: nil, runner: missing.runner).customDerivedDataLocation() == nil)
        #expect(missing.calls.isEmpty)
    }

    @Test func theEnvironmentScanUsesTheHomesDerivedData() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile("Library/Developer/Xcode/DerivedData/ModuleCache.noindex/x", kibibytes: 4)
        var environment = home.environment()
        environment.tools.defaults = URL(fileURLWithPath: "/fake/bin/defaults")
        let unset = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(exitCode: 1) }

        let report = await DerivedDataScanner.scan(environment: environment, runner: unset.runner)
        #expect(report.root == home.url.appending(path: "Library/Developer/Xcode/DerivedData").path)
        #expect(report.entries.map(\.state) == [.noInfoPlist])
        #expect(unset.calls.count == 1)
    }
}
