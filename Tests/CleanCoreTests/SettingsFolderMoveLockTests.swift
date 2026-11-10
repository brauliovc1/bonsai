@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §10.2: the move takes the old folder's locks (waited for, never broken), and afterwards an older binary
/// going through `clean-claude` meets the same lock files. The other process is `/usr/bin/lockf` (flock, as
/// `FileLock`). Temp folders only.
@Suite("Settings folder move: locks")
struct SettingsFolderMoveLockTests {
    /// Held by another process: the move waits and happens after it is let go. The other process looks at
    /// clean-claude right before it lets go: still a folder.
    @Test(arguments: ["cleanup.lock", "settings.lock"])
    func aLockHeldElsewhereIsWaitedFor(_ name: String) throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let inodes = world.inodes(world.old)
        let seen = world.home.url.appending(path: "seen-while-held")
        let holder = try LockHolder(world.old.appending(path: name),
                                    thenRun: #"/usr/bin/stat -f %HT "$1" > "$2""#, arguments: [world.old.path, seen.path])
        defer { holder.release() }

        let library = world.library
        let moved = Shared<SettingsFolderMove.Outcome?>(nil)
        let mover = TestThreads()
        mover.start { moved.change { $0 = SettingsFolderMove.run(in: library, lockTimeout: TestWait.limit).outcome } }
        #expect(!mover.join(timeout: .milliseconds(500)), "the move waits while \(name) is held")
        #expect(holder.release(), "the other process let go of \(name)")
        #expect(mover.join(timeout: TestWait.limit), "the move didn't finish within \(TestWait.limit) once \(name) was free")

        #expect(moved.value == .moved)
        #expect(try String(contentsOf: seen, encoding: .utf8) == "Directory\n", "not moved while \(name) was held")
        #expect(world.entry(world.old) == .link("Bonsai"))
        #expect(world.inodes(world.new) == inodes, "the lock file the other process held is the same file")
    }

    /// Not free in time: nothing changes this launch (the old folder is used) and the next launch moves it.
    @Test func aLockNotFreeInTimeLeavesTheMoveForTheNextLaunch() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let before = try world.snapshot(world.old)
        let holder = try LockHolder(world.old.appending(path: "cleanup.lock"))
        defer { holder.release() }

        let result = world.move(timeout: .milliseconds(200))

        guard case .notMoved = result.outcome else {
            Issue.record("expected notMoved, got \(result.outcome)")
            return
        }
        #expect(result.folder == world.old)
        #expect(result.notice?.contains("tries again next launch") == true, "\(result.notice ?? "")")
        #expect(world.entry(world.old) == .folder && world.entry(world.new) == .missing)
        #expect(try world.snapshot(world.old) == before, "the lock wasn't broken and nothing changed")
        #expect(holder.release(), "the other process let go of cleanup.lock")
        #expect(world.move().outcome == .moved)
    }

    /// After the move, an older binary opens clean-claude/<lock>: through the link it is the same file, so the
    /// two still exclude each other. Both ways, two processes.
    @Test func anOldBinaryThroughTheLinkMeetsTheSameLocks() throws {
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        #expect(world.move().outcome == .moved)

        for name in ["cleanup.lock", "settings.lock"] {
            let oldPath = world.old.appending(path: name), newPath = world.new.appending(path: name)
            let held = try #require(try FileLock.tryLock(newPath, createsFolder: false))
            #expect(try lockfStatus(oldPath) == 75, "\(name): held here by the new path, the other process can't take it")
            held.release()
            #expect(try lockfStatus(oldPath) == 0, "\(name)")

            let holder = try LockHolder(oldPath)
            defer { holder.release() }
            #expect(try FileLock.tryLock(newPath, createsFolder: false) == nil, "\(name): held there by the old path")
            #expect(holder.release(), "\(name): the other process let go")
            #expect(try FileLock.tryLock(newPath, createsFolder: false) != nil, "\(name)")
        }
        #expect(world.entry(world.old) == .link("Bonsai"), "no folder of its own was made at the old path")
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.library.path).sorted() == ["Bonsai", "clean-claude"])
    }
}
