@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §10.2: what the move does with each state of the two folders. Temp folders only.
@Suite("Settings folder move")
struct SettingsFolderMoveTests {
    /// Old only: one rename, a link back, every file the same inode and contents.
    @Test func theOldFolderIsMovedAndLinked() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let inodes = world.inodes(world.old)
        let before = try world.snapshot(world.old)

        let result = world.move()

        #expect(result.outcome == .moved)
        #expect(result.folder == world.new)
        #expect(result.notice == nil)
        #expect(world.entry(world.new) == .folder)
        #expect(world.entry(world.old) == .link("Bonsai"), "clean-claude -> Bonsai")
        #expect(world.inodes(world.new) == inodes, "moved, not copied: the folder and every file keep their inodes")
        #expect(try world.snapshot(world.new) == before, "log, settings and locks intact")
        #expect(try world.snapshot(world.old) == before, "the same files through the link")
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.library.path).sorted() == ["Bonsai", "clean-claude"])
    }

    /// New only: nothing happens. Neither: nothing is made either.
    @Test func newOnlyOrNeitherNothingHappens() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        let empty = world.move()
        #expect(empty.outcome == .nothingToMove && empty.folder == world.new && empty.notice == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.library.path).isEmpty, "nothing made")

        try world.makeFolder(world.new, tag: "new")
        let before = try world.snapshot(world.new)
        let result = world.move()
        #expect(result.outcome == .nothingToMove && result.folder == world.new && result.notice == nil)
        #expect(world.entry(world.old) == .missing)
        #expect(try world.snapshot(world.new) == before)
    }

    /// Both real folders: Bonsai is used, neither is touched, and it says so in one notice.
    @Test func bothRealFoldersNeitherIsTouched() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        try world.makeFolder(world.new, tag: "new")
        let old = try world.snapshot(world.old), new = try world.snapshot(world.new)

        let result = world.move()

        #expect(result.outcome == .bothExist)
        #expect(result.folder == world.new)
        let notice = try #require(result.notice)
        #expect(notice.contains(world.old.path) && notice.contains(world.new.path), "\(notice)")
        #expect(notice.contains("Bonsai uses Bonsai and leaves clean-claude as it is"), "\(notice)")
        #expect(try world.snapshot(world.old) == old)
        #expect(try world.snapshot(world.new) == new)
        #expect(world.entry(world.old) == .folder && world.entry(world.new) == .folder)
    }

    /// The old one is a link already (after a move, or made by hand): no change.
    @Test func theOldOneIsALinkAlready() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.new, tag: "new")
        try FileManager.default.createSymbolicLink(atPath: world.old.path, withDestinationPath: "Bonsai")
        let before = try world.snapshot(world.new)

        let result = world.move()

        #expect(result.outcome == .nothingToMove && result.folder == world.new && result.notice == nil)
        #expect(world.entry(world.old) == .link("Bonsai"))
        #expect(try world.snapshot(world.new) == before)

        // A link somewhere else stays as it is too.
        let elsewhere = world.home.url.appending(path: "elsewhere", directoryHint: .isDirectory)
        try world.makeFolder(elsewhere, tag: "elsewhere")
        try FileManager.default.removeItem(at: world.old)
        try FileManager.default.createSymbolicLink(atPath: world.old.path, withDestinationPath: elsewhere.path)
        #expect(world.move().outcome == .nothingToMove)
        #expect(world.entry(world.old) == .link(elsewhere.path))
    }

    /// A move stopped between making its link and the swap leaves `Bonsai -> Bonsai`: the next one goes on.
    @Test func aLinkLeftByAStoppedMoveIsReplaced() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        try FileManager.default.createSymbolicLink(atPath: world.new.path, withDestinationPath: "Bonsai")
        let inodes = world.inodes(world.old)

        #expect(world.move().outcome == .moved)
        #expect(world.inodes(world.new) == inodes)
        #expect(world.entry(world.old) == .link("Bonsai"))
    }

    /// At launch: only when no settings folder is named in the environment (new or old name).
    @Test func launchMovesOnlyTheDefaultFolder() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let elsewhere = world.home.url.appending(path: "dev-settings").path
        for name in ["BONSAI_SETTINGS_DIR", "CLEAN_CLAUDE_SETTINGS_DIR"] {
            let (environment, notice) = CleanEnvironment.launch(
                homeDirectory: world.home.url, variables: [name: elsewhere], tools: ToolPaths()
            )
            #expect(environment.settingsDirectory.path == elsewhere && notice == nil, "\(name)")
            #expect(world.entry(world.old) == .folder && world.entry(world.new) == .missing, "\(name): not moved")
        }

        let (environment, notice) = CleanEnvironment.launch(homeDirectory: world.home.url, variables: [:], tools: ToolPaths())
        #expect(notice == nil)
        #expect(CanonicalPath.same(environment.settingsDirectory, world.new))
        #expect(world.entry(world.old) == .link("Bonsai"))
        let settings = SettingsStore(environment: environment).fileURL
        #expect(try String(contentsOf: settings, encoding: .utf8) == "old settings.json\n", "the old folder's file")
    }
}
