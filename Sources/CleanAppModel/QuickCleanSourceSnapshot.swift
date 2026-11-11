import CleanCore
import Darwin
import Foundation

/// Only source-location metadata: no index, refs, logs or objects. Reads cannot follow links or block on pipes.
struct QuickCleanSourceSnapshot: Sendable, Equatable {
    let domains: [String]
    let entries: [String: Stamp]

    static func capture(_ fence: QuickCleanSourceFence) throws -> Self {
        let settings = try SettingsStore(environment: fence.environment).load()
        let current = Scanner.resolveRoots(explicit: [], environment: fence.environment, settings: settings)
        let domains = Array(Set((fence.roots + current).map(CanonicalPath.resolve))).sorted()
        var reader = Reader()
        let repos = Array(Set((fence.repositories + fence.worktrees.map(\.repoPath)).map(CanonicalPath.resolve))).sorted()
        for repo in repos {
            try reader.directory(repo)
            let marker = try reader.record(repo + "/.git", optional: true)
            let git: String
            if marker.mode == S_IFDIR { git = repo + "/.git" }
            else if let bytes = marker.bytes { git = try pointer(bytes, prefix: "gitdir: ", parent: repo) }
            else if fence.worktrees.contains(where: { $0.isBare && CanonicalPath.same($0.repoURL, URL(fileURLWithPath: repo)) }) { git = repo }
            else { throw Failure("The source checkout's .git marker is missing: " + repo) }
            try reader.directory(git)
            let commonFile = try reader.record(git + "/commondir", optional: true)
            let common = try commonFile.bytes.map { try pointer($0, prefix: "", parent: git) } ?? git
            try reader.directory(common)
            for file in Set([git + "/config.worktree", common + "/config", common + "/config.worktree"]) {
                _ = try reader.record(file, optional: true)
            }
            let registry = common + "/worktrees"
            if try reader.directory(registry, optional: true) {
                for name in try reader.children(registry) {
                    let folder = registry + "/" + name
                    let entry = try reader.record(folder)
                    guard entry.mode == S_IFDIR else { continue }
                    _ = try reader.record(folder + "/gitdir")
                    _ = try reader.record(folder + "/commondir", optional: true)
                    _ = try reader.record(folder + "/config.worktree", optional: true)
                }
            }
        }
        for tree in fence.worktrees {
            if try reader.directory(CanonicalPath.resolve(tree.url), optional: true) {
                _ = try reader.record(CanonicalPath.resolve(tree.url) + "/.git", optional: true)
            }
        }
        return Self(domains: domains, entries: reader.entries)
    }

    /// Git formats pointers as one path followed by a newline. A path's spaces and tabs are significant.
    private static func pointer(_ bytes: Data, prefix: String, parent: String) throws -> String {
        guard var text = String(data: bytes, encoding: .utf8), text.hasPrefix(prefix), !text.contains("\0") else {
            throw Failure("A source Git-directory pointer could not be read.")
        }
        text.removeFirst(prefix.count)
        if text.hasSuffix("\r\n") { text.removeLast(2) }
        else if text.hasSuffix("\n") { text.removeLast() }
        guard !text.isEmpty else { throw Failure("A source Git-directory pointer is empty.") }
        return (text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(fileURLWithPath: parent).appending(path: text)).standardizedFileURL.path
    }

    static func registrationName(_ bytes: [UInt8]) throws -> String {
        guard let name = String(bytes: bytes, encoding: .utf8) else { throw Failure("A source registration name is not valid UTF-8.") }
        return name
    }

    struct Stamp: Sendable, Equatable {
        let device: Int32
        let inode: UInt64
        let mode: mode_t
        let bytes: Data?
        static let missing = Stamp(device: 0, inode: 0, mode: 0, bytes: nil)
    }

    private struct Reader {
        var entries: [String: Stamp] = [:]
        var totalBytes = 0
        static let entryLimit = 8_192
        static let byteLimit = 2 * 1_024 * 1_024
        static let fileLimit = 65_536

        @discardableResult mutating func directory(_ path: String, optional: Bool = false) throws -> Bool {
            let stamp = try record(path, optional: optional)
            if stamp == .missing { return false }
            guard stamp.mode == S_IFDIR else { throw Failure("Source metadata is not a real directory: " + path) }
            return true
        }

        mutating func record(_ path: String, optional: Bool = false) throws -> Stamp {
            if let existing = entries[path] { return existing }
            guard entries.count < Self.entryLimit else { throw Failure("There is too much source metadata to verify safely.") }
            var info = stat()
            guard lstat(path, &info) == 0 else {
                guard optional && errno == ENOENT else { throw Failure("Source metadata could not be read: " + path) }
                entries[path] = .missing
                return .missing
            }
            let mode = info.st_mode & S_IFMT
            guard mode == S_IFDIR || mode == S_IFREG else { throw Failure("Source metadata is not a real file or directory: " + path) }
            let bytes = mode == S_IFREG ? try read(path, identity: info) : nil
            let stamp = Stamp(device: info.st_dev, inode: info.st_ino, mode: mode, bytes: bytes)
            entries[path] = stamp
            return stamp
        }

        mutating func children(_ path: String) throws -> [String] {
            guard let directory = opendir(path) else { throw Failure("Source registrations could not be read: " + path) }
            defer { closedir(directory) }
            var names: [String] = []
            errno = 0
            while let entry = readdir(directory) {
                let bytes = withUnsafeBytes(of: entry.pointee.d_name) { buffer in Array(buffer.prefix(Int(entry.pointee.d_namlen))) }
                let name = try QuickCleanSourceSnapshot.registrationName(bytes)
                if name == "." || name == ".." { continue }
                names.append(name)
                guard names.count + entries.count < Self.entryLimit else { throw Failure("There are too many source registrations to verify safely.") }
            }
            guard errno == 0 else { throw Failure("Source registrations changed or could not be read: " + path) }
            names.sort()
            let listing = Data(names.joined(separator: "\0").utf8)
            totalBytes += listing.count
            guard totalBytes <= Self.byteLimit else { throw Failure("There is too much source metadata to verify safely.") }
            entries["listing:" + path] = Stamp(device: 0, inode: 0, mode: S_IFDIR, bytes: listing)
            return names
        }

        mutating func read(_ path: String, identity: stat) throws -> Data {
            guard identity.st_size >= 0 && identity.st_size <= Self.fileLimit else { throw Failure("A source metadata file exceeds the safe size limit: " + path) }
            let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw Failure("Source metadata could not be opened: " + path) }
            defer { close(descriptor) }
            var before = stat()
            guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
                  before.st_dev == identity.st_dev, before.st_ino == identity.st_ino else { throw Failure("Source metadata was replaced: " + path) }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                if count == 0 { break }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure("Source metadata could not be read: " + path) }
                data.append(contentsOf: buffer.prefix(count))
                guard data.count <= Self.fileLimit, totalBytes + data.count <= Self.byteLimit else { throw Failure("Source metadata exceeds the safe size limit.") }
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0, after.st_size == before.st_size,
                  after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec, after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else {
                throw Failure("Source metadata changed while it was being read: " + path)
            }
            var currentPath = stat()
            guard lstat(path, &currentPath) == 0, currentPath.st_dev == before.st_dev, currentPath.st_ino == before.st_ino,
                  currentPath.st_mode & S_IFMT == S_IFREG else { throw Failure("Source metadata was replaced while it was being read: " + path) }
            totalBytes += data.count
            return data
        }
    }

    struct Failure: Error, Sendable, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
