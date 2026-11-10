@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12c review: what is at each path decides the move, and the notice never says to delete anything. Temp
/// folders only.
@Suite("Settings folder move: what is in the way")
struct SettingsFolderMoveEdgeTests {
    enum InTheWay: String, CaseIterable, Sendable {
        /// `Bonsai -> clean-claude`: Bonsai IS clean-claude.
        case linkToOld
        case linkElsewhere
        case file
    }

    /// Anything at Bonsai that isn't a second real folder: no move, clean-claude is used, nothing is touched.
    @Test(arguments: InTheWay.allCases)
    func somethingElseAtBonsaiIsNeverASecondFolder(_ thing: InTheWay) throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        switch thing {
        case .linkToOld:
            try FileManager.default.createSymbolicLink(atPath: world.new.path, withDestinationPath: "clean-claude")
        case .linkElsewhere:
            let elsewhere = world.home.url.appending(path: "elsewhere", directoryHint: .isDirectory)
            try world.makeFolder(elsewhere, tag: "elsewhere")
            try FileManager.default.createSymbolicLink(atPath: world.new.path, withDestinationPath: elsewhere.path)
        case .file:
            try Data("not a folder\n".utf8).write(to: world.new)
        }
        let old = try world.snapshot(world.old), atNew = world.entry(world.new)

        let result = world.move()

        guard case .notMoved = result.outcome else {
            Issue.record("\(thing): \(result.outcome)")
            return
        }
        #expect(result.folder == world.old, "\(thing): uses clean-claude")
        let notice = try #require(result.notice)
        #expect(notice.contains(world.old.path) && notice.contains(world.new.path), "\(notice)")
        #expect(!notice.lowercased().contains("delete"), "\(notice)")
        #expect(try world.snapshot(world.old) == old)
        #expect(world.entry(world.old) == .folder && world.entry(world.new) == atNew)
    }

    /// Another `bonsai` folder (any letter case) on a disk that doesn't tell the cases apart is not Bonsai's.
    @Test func aFolderNamedLowercaseBonsaiIsNotBonsais() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let other = world.library.appending(path: "bonsai", directoryHint: .isDirectory)
        try world.makeFolder(other, tag: "another app")
        let before = try world.snapshot(other)

        let result = world.move()

        if world.entry(world.new) == .missing {
            #expect(result.outcome == .moved, "a case-sensitive disk: Bonsai is free")
            return
        }
        guard case .notMoved = result.outcome else {
            Issue.record("\(result.outcome)")
            return
        }
        #expect(result.folder == world.old)
        #expect(result.notice?.contains("a folder named bonsai") == true, "\(result.notice ?? "")")
        #expect(try world.snapshot(other) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.library.path).sorted() == ["bonsai", "clean-claude"])
    }

    /// clean-claude is a link to a folder elsewhere: it is used where it is and not moved (older binaries keep
    /// using it too, with the same locks). A link that leads nowhere holds nothing: Bonsai is used.
    @Test func anOldFolderLinkedElsewhereIsUsedWhereItIs() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        let elsewhere = world.home.url.appending(path: "Dropbox/clean-claude", directoryHint: .isDirectory)
        try world.makeFolder(elsewhere, tag: "old")
        try FileManager.default.createSymbolicLink(atPath: world.old.path, withDestinationPath: elsewhere.path)
        let before = try world.snapshot(elsewhere)

        let result = world.move()

        guard case .notMoved = result.outcome else {
            Issue.record("\(result.outcome)")
            return
        }
        #expect(result.folder == world.old)
        #expect(try String(contentsOf: result.folder.appending(path: "removals.jsonl"), encoding: .utf8) == "old removals.jsonl\n")
        #expect(result.notice?.contains(elsewhere.path) == true, "\(result.notice ?? "")")
        #expect(world.entry(world.new) == .missing && world.entry(world.old) == .link(elsewhere.path))
        #expect(try world.snapshot(elsewhere) == before)

        try FileManager.default.removeItem(at: elsewhere)
        let dangling = world.move()
        #expect(dangling.outcome == .nothingToMove && dangling.folder == world.new)
    }

    /// A move that stopped between its two steps left `Bonsai -> Bonsai`, and clean-claude is gone: the link is
    /// removed, so Bonsai can be made and written.
    @Test func aLeftoverLinkWithoutTheOldFolderIsRemoved() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try FileManager.default.createSymbolicLink(atPath: world.new.path, withDestinationPath: "Bonsai")

        let result = world.move()

        #expect(result.outcome == .nothingToMove && result.folder == world.new)
        #expect(world.entry(world.new) == .missing)
        try SettingsStore(directory: result.folder).save(Settings())
        #expect(try SettingsStore(directory: result.folder).load() == Settings())
    }

    /// Any settings folder variable in the environment, even empty, means the folder was chosen by hand: nothing
    /// is moved. Which folder is used keeps its rule (empty counts as unset).
    @Test func anySettingsVariableEvenEmptyStopsTheMove() throws {
        for (variables, used) in [
            (["BONSAI_SETTINGS_DIR": ""], "Library/Application Support/Bonsai"),
            (["CLEAN_CLAUDE_SETTINGS_DIR": ""], "Library/Application Support/Bonsai"),
            (["BONSAI_SETTINGS_DIR": "", "CLEAN_CLAUDE_SETTINGS_DIR": "/tmp/x"], "/tmp/x"),
        ] {
            let world = try SettingsFolderWorld()
            defer { world.remove() }
            try world.makeFolder(world.old, tag: "old")
            let (environment, notice) = CleanEnvironment.launch(homeDirectory: world.home.url, variables: variables,
                                                                tools: ToolPaths())
            #expect(notice == nil)
            #expect(environment.settingsDirectory.path.hasSuffix(used), "\(variables): \(environment.settingsDirectory.path)")
            #expect(world.entry(world.old) == .folder && world.entry(world.new) == .missing, "\(variables): not moved")
        }
    }
}
