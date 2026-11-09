import Foundation

/// `sizes.json` in the settings folder (PLAN §3): `du` estimates of folders, so a screen that lists many
/// folders doesn't measure every unchanged one again. An entry is used only while lstat still finds the same
/// folder (device and inode) with the same modification time, and for at most `maxAge`; anything else is
/// measured again. A file that can't be read is an empty cache, and a write replaces the file atomically
/// (two writers: the last one wins, which is fine for a cache). Sizes are estimates either way; what a delete
/// frees is measured from the volume.
public struct FolderSizeCache: Sendable {
    public static let fileName = "sizes.json"
    public static let maxAge: TimeInterval = 86_400

    struct Entry: Codable, Hashable, Sendable {
        var bytes: Int64
        var measuredAt: Date
        /// The folder's own mtime and identity when it was measured.
        var modified: TimeInterval
        var device: Int32
        var inode: UInt64
    }

    /// What lstat says about a folder now; nil when it isn't a folder.
    struct Stamp: Hashable, Sendable {
        var modified: TimeInterval
        var device: Int32
        var inode: UInt64

        static func of(_ path: String) -> Stamp? {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
            let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
            return Stamp(modified: modified, device: info.st_dev, inode: info.st_ino)
        }
    }

    public var fileURL: URL
    public var now: @Sendable () -> Date

    public init(environment: CleanEnvironment) {
        fileURL = environment.settingsDirectory.appending(path: Self.fileName)
        now = environment.now
    }

    /// Sizes by path: still-valid cached ones, the rest measured with `du` (`maxConcurrent` at a time) and
    /// stored. A folder that is gone, or that `du` can't measure, is left out.
    public func sizes(
        of folders: [URL],
        du: URL,
        maxConcurrent: Int = 4,
        onFinished: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> [String: Int64] {
        let date = now()
        let cached = load()
        var sizes: [String: Int64] = [:]
        var stamps: [String: Stamp] = [:]
        var missing: [URL] = []
        for folder in folders {
            guard let stamp = Stamp.of(folder.path) else { continue }
            stamps[folder.path] = stamp
            if let entry = cached[folder.path], Self.isValid(entry, stamp: stamp, now: date) {
                sizes[folder.path] = entry.bytes
            } else {
                missing.append(folder)
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
            if let stamp = stamps[path] {
                fresh[path] = Entry(bytes: bytes, measuredAt: date, modified: stamp.modified, device: stamp.device, inode: stamp.inode)
            }
        }
        if !fresh.isEmpty { save(adding: fresh, now: date) }
        return sizes
    }

    static func isValid(_ entry: Entry, stamp: Stamp, now: Date) -> Bool {
        let age = now.timeIntervalSince(entry.measuredAt)
        return age >= 0 && age < maxAge
            && entry.modified == stamp.modified && entry.device == stamp.device && entry.inode == stamp.inode
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
