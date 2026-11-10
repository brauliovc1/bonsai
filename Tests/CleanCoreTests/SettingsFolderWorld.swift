@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// A temp home whose `Library/Application Support` stands for the real one in the settings folder's move (PLAN
/// §10.2). Nothing here touches the real folders.
struct SettingsFolderWorld {
    let home: TemporaryDirectory
    var library: URL { home.url.appending(path: "Library/Application Support", directoryHint: .isDirectory) }
    var old: URL { library.appending(path: "clean-claude", directoryHint: .isDirectory) }
    var new: URL { library.appending(path: "Bonsai", directoryHint: .isDirectory) }
    /// The files a settings folder holds (PLAN §3).
    static let files = ["settings.json", "removals.jsonl", "sizes.json", "cleanup.lock", "settings.lock"]

    init() throws {
        home = try TemporaryDirectory(prefix: "bonsai-move-home")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    func remove() {
        home.remove()
    }

    /// A settings folder with every file, each holding its own text (lock files are empty).
    func makeFolder(_ folder: URL, tag: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in Self.files {
            let text = name.hasSuffix(".lock") ? "" : "\(tag) \(name)\n"
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
    }

    func move(timeout: Duration = TestWait.limit) -> SettingsFolderMove.Result {
        SettingsFolderMove.run(in: library, lockTimeout: timeout)
    }

    /// What `lstat` finds at `url`.
    func entry(_ url: URL) -> SettingsFolderMove.Entry {
        SettingsFolderMove.Entry(url)
    }

    /// Every entry under `folder` (links not followed): its path, inode, size, mtime and contents. Equal
    /// snapshots = nothing was touched.
    func snapshot(_ folder: URL) throws -> [String] {
        var lines: [String] = []
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        for name in names {
            let url = folder.appending(path: name)
            var info = stat()
            #expect(lstat(url.path, &info) == 0)
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? "-"
            lines.append("\(name) \(info.st_ino) \(info.st_size) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec) \(contents)")
        }
        return lines
    }

    /// Inode of each file under `folder`, by name, and of the folder itself under ".".
    func inodes(_ folder: URL) -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        for name in Self.files + ["."] {
            var info = stat()
            if lstat(folder.appending(path: name).path, &info) == 0 { result[name] = info.st_ino }
        }
        return result
    }
}

/// Another process holding a lock file the way an older Bonsai does (`flock`, through `/usr/bin/lockf -k`) until the
/// test lets it go: it waits on a pipe only this process writes to, never on a timer, so it also lets go when the
/// test process ends. `command` (a shell line; `arguments` are its $1, $2…) runs once it is let go, while it still
/// holds the lock. Returns once the child holds it.
final class LockHolder {
    private let process = Process()
    private let input = Pipe()
    private let ended = DispatchSemaphore(value: 0)

    init(_ file: URL, thenRun command: String = ":", arguments: [String] = []) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
        process.arguments = ["-k", file.path, "/bin/sh", "-c", "read line; \(command)", "sh"] + arguments
        process.standardInput = input
        process.terminationHandler = { [ended] _ in ended.signal() }
        try process.run()
        let deadline = Date(timeIntervalSinceNow: TestWait.seconds)
        while Date() < deadline {
            guard let probe = try FileLock.tryLock(file, createsFolder: false) else { return }
            probe.release()
            usleep(10_000)
        }
        release()
        throw LockHolderError(description: "lockf didn't take \(file.path) within \(TestWait.limit)")
    }

    /// Lets it go (its command runs, then the lock is free) and waits until it has ended: false when it is still
    /// running after `TestWait.limit`. Later calls return at once.
    @discardableResult
    func release() -> Bool {
        try? input.fileHandleForWriting.close()
        guard ended.wait(timeout: TestWait.deadline) == .success else { return false }
        ended.signal()
        return true
    }
}

/// `lockf -k -s -t 0 <file> true`: 0 when it could take the lock at once, 75 when another holder has it.
func lockfStatus(_ file: URL) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
    process.arguments = ["-k", "-s", "-t", "0", file.path, "/usr/bin/true"]
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

struct LockHolderError: Error, CustomStringConvertible {
    var description: String
}
