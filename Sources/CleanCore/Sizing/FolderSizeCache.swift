import Foundation

/// `sizes.json` in the settings folder (PLAN §3): `du` estimates of folders, so a screen that lists many
/// folders doesn't measure every unchanged one again. An entry is used only while lstat still finds the same
/// folder (device and inode) with the same modification time, and the same first-level entries with the same
/// modification times (a new file in `node_modules/react` or `.next/cache` moves those); for at most `maxAge`;
/// and while the removal log has nothing newer for its checkout (a light clean or a worktree removal, by the app
/// or the CLI). Anything else is measured again. Deeper changes go unseen until then: sizes are estimates, and
/// what a delete frees is measured from the volume. A file that can't be read is an empty cache, and a write
/// replaces the file atomically (two writers: the last one wins, which is fine for a cache).
public struct FolderSizeCache: Sendable {
    public static let fileName = "sizes.json"
    public static let maxAge: TimeInterval = 3_600

    /// A folder to measure and the checkout it is in (as git printed it), for the log check.
    public struct Folder: Sendable, Hashable {
        public var url: URL
        public var checkout: String

        public init(url: URL, checkout: String) {
            self.url = url
            self.checkout = checkout
        }
    }

    struct Entry: Codable, Hashable, Sendable {
        var bytes: Int64
        var measuredAt: Date
        var stamp: Stamp
    }

    /// What lstat says about a folder and its first-level entries now.
    struct Stamp: Codable, Hashable, Sendable {
        var modified: TimeInterval
        var device: Int32
        var inode: UInt64
        var childCount: Int
        /// The first-level entries' mtimes added up: any one of them moving changes it.
        var childModifiedSum: TimeInterval

        /// nil when it isn't a folder or can't be read.
        static func of(_ path: String) -> Stamp? {
            guard let own = lstatTimes(path), own.isDirectory, let children = DirectoryEntries.read(path) else { return nil }
            let sum = children.reduce(0.0) { $0 + (lstatTimes(path + "/" + $1.name)?.modified ?? -1) }
            return Stamp(modified: own.modified, device: own.device, inode: own.inode, childCount: children.count, childModifiedSum: sum)
        }

        private static func lstatTimes(_ path: String) -> (modified: TimeInterval, device: Int32, inode: UInt64, isDirectory: Bool)? {
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
            return (modified, info.st_dev, info.st_ino, info.st_mode & S_IFMT == S_IFDIR)
        }
    }

    public var fileURL: URL
    public var now: @Sendable () -> Date

    public init(environment: CleanEnvironment) {
        fileURL = environment.settingsDirectory.appending(path: Self.fileName)
        now = environment.now
    }

    /// Sizes by path: still-valid cached ones, the rest measured with `du` (`maxConcurrent` at a time) and
    /// stored. `log`: the removal log; an entry newer than a measurement, at or inside that folder's checkout
    /// (or the checkout inside it), makes the measurement stale. A folder that is gone, or that `du` can't
    /// measure, is left out.
    public func sizes(
        of folders: [Folder],
        du: URL,
        log: [RemovalLogEntry] = [],
        maxConcurrent: Int = 4,
        onFinished: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> [String: Int64] {
        let date = now()
        let cached = load()
        let recent = log.filter { date.timeIntervalSince($0.date) < Self.maxAge }
        var sizes: [String: Int64] = [:]
        var stamps: [String: Stamp] = [:]
        var missing: [URL] = []
        for folder in folders {
            guard let stamp = Stamp.of(folder.url.path) else { continue }
            stamps[folder.url.path] = stamp
            if let entry = cached[folder.url.path], Self.isValid(entry, stamp: stamp, now: date),
               !Self.isTouched(entry, checkout: folder.checkout, log: recent) {
                sizes[folder.url.path] = entry.bytes
            } else {
                missing.append(folder.url)
            }
        }
        let hits = sizes.count
        let total = hits + missing.count
        let measured = await DirectorySizer(du: du, maxConcurrent: maxConcurrent).sizes(of: missing) { completed, _ in
            onFinished(hits + completed, total)
        }.sizes
        var fresh: [String: Entry] = [:]
        for (path, bytes) in measured {
            sizes[path] = bytes
            // The stamp from before du: a folder that changed while it was measured is measured again next time.
            if let stamp = stamps[path] { fresh[path] = Entry(bytes: bytes, measuredAt: date, stamp: stamp) }
        }
        if !fresh.isEmpty { save(adding: fresh, now: date) }
        return sizes
    }

    static func isValid(_ entry: Entry, stamp: Stamp, now: Date) -> Bool {
        let age = now.timeIntervalSince(entry.measuredAt)
        return age >= 0 && age < maxAge && entry.stamp == stamp
    }

    /// A cleanup logged after the measurement touched the folder's checkout.
    static func isTouched(_ entry: Entry, checkout: String, log: [RemovalLogEntry]) -> Bool {
        let checkoutURL = URL(fileURLWithPath: checkout, isDirectory: true)
        return log.contains { logged in
            guard logged.date >= entry.measuredAt else { return false }
            let path = URL(fileURLWithPath: logged.path, isDirectory: true)
            return CanonicalPath.same(path, checkoutURL) || CanonicalPath.isInside(path, directory: checkoutURL)
                || CanonicalPath.isInside(checkoutURL, directory: path)
        }
    }

    func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? CleanJSON.decoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    /// Merges into what the file holds now and drops entries older than `maxAge`. Failures are ignored.
    private func save(adding fresh: [String: Entry], now: Date) {
        var entries = load().filter { now.timeIntervalSince($0.value.measuredAt) < Self.maxAge }
        entries.merge(fresh) { _, new in new }
        guard let data = try? CleanJSON.encoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
