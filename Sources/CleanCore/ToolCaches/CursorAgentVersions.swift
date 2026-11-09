import Foundation

/// Which of Cursor's agent command-line versions may go (PLAN §4.6): only folders named like a version
/// (`2026.10.19-6bbf2c4`: `^\d{4}\.\d{1,2}\.\d{1,2}-[0-9a-f]+$`) count; every one may go except the version
/// `.local/bin/cursor-agent` names directly, the one its full chain of links resolves into, and the newest (by date,
/// ties by modification date). Folders with other names (`latest`, `*.partial`) are never deleted and never count as
/// the newest. A link that is missing, dangling or resolving anywhere but into a folder of `versions/` refuses the
/// whole entry.
///
/// Beyond the table: a version whose `.running` folder holds a file named after a live process (the agent
/// marks the version each running copy uses) is kept too, and so is one with anything else in `.running`.
public struct CursorAgentVersions: Sendable, Hashable {
    public struct Kept: Sendable, Hashable, Codable {
        public var name: String
        public var reason: String
    }

    public static let versionsPath = ToolCacheCatalog.agentCLI + "/share/cursor-agent/versions"
    public static let linkPath = ToolCacheCatalog.agentCLI + "/bin/cursor-agent"

    /// The version folders that may go, sorted by name.
    public var removable: [String]
    public var kept: [Kept]

    enum Resolution: Sendable, Hashable {
        case resolved(CursorAgentVersions)
        case refused(String)
    }

    /// Reads the link and the versions folder. The versions folder must already have passed the path check.
    static func resolve(home: URL, isAlive: (Int32) -> Bool = processIsAlive) -> Resolution {
        let link = home.appending(path: linkPath)
        let shownLink = TildePath.abbreviate(link.path, home: home)
        switch ToolCachePathCheck.check(linkPath, home: home, expect: .link) {
        case .missing: return .refused("the cursor-agent link (\(shownLink)) is missing, so the version in use is unknown")
        case .refused(let why): return .refused(why)
        case .passed: break
        }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return .refused("the cursor-agent link (\(shownLink)) can't be read")
        }
        let absolute = destination.hasPrefix("/") ? destination : link.deletingLastPathComponent().path + "/" + destination
        guard let resolved = realpath(absolute, nil) else {
            return .refused("the cursor-agent link points to something that doesn't exist (\(destination))")
        }
        let target = String(cString: resolved)
        free(resolved)
        let versions = home.appending(path: versionsPath, directoryHint: .isDirectory)
        guard let relative = CanonicalPath.relativePath(of: URL(fileURLWithPath: target), to: versions), relative != "." else {
            return .refused("the cursor-agent link points outside the versions folder (\(destination))")
        }
        let inUse = String(relative.split(separator: "/")[0])
        guard let listing = DirectoryEntries.read(versions.path) else {
            return .refused("\(TildePath.abbreviate(versions.path, home: home)) can't be read")
        }
        // Only real folders can be versions; links, files and other names are left alone.
        let folders = listing.filter { $0.kind == .directory }.map(\.name)
        guard folders.contains(inUse) else {
            return .refused("the cursor-agent link points into \(inUse), which is not a version folder")
        }
        let named = directlyNamed(absolute, versions: versions)
        let dated = folders.compactMap { name in VersionName(name).map { (name: name, key: $0) } }
            .map { (name: $0.name, key: $0.key, modified: modificationDate(versions.path + "/" + $0.name)) }
            .sorted { ($0.key, $0.modified, $0.name) < ($1.key, $1.modified, $1.name) }
        let newest = dated.last?.name

        var kept: [Kept] = []
        var removable: [String] = []
        for name in dated.map(\.name) {
            var reasons: [String] = []
            if name == named, name != inUse { reasons.append("the version the cursor-agent link names") }
            if name == inUse { reasons.append("the version in use") }
            if name == newest { reasons.append("the newest") }
            if reasons.isEmpty, let marker = runningMarker(versions.path + "/" + name, isAlive: isAlive) {
                reasons.append(marker)
            }
            if reasons.isEmpty {
                removable.append(name)
            } else {
                kept.append(Kept(name: name, reason: reasons.joined(separator: " and ")))
            }
        }
        for name in [named, inUse].compactMap({ $0 }) where !dated.contains(where: { $0.name == name }) && !kept.contains(where: { $0.name == name }) {
            kept.append(Kept(name: name, reason: name == inUse ? "the version in use" : "the version the cursor-agent link names"))
        }
        return .resolved(CursorAgentVersions(removable: removable, kept: kept))
    }

    /// The folder of `versions/` the link's own target sits in (`versions/X/cursor-agent` names X, even when that
    /// file is itself a link into another version); nil when the target isn't inside `versions/`.
    static func directlyNamed(_ target: String, versions: URL) -> String? {
        let parent = (target as NSString).deletingLastPathComponent
        guard let real = realpath(parent, nil) else { return nil }
        defer { free(real) }
        let candidate = String(cString: real) + "/" + (target as NSString).lastPathComponent
        let base = CanonicalPath.resolve(versions)
        guard candidate.hasPrefix(base + "/") else { return nil }
        return candidate.dropFirst(base.count + 1).split(separator: "/").first.map(String.init)
    }

    /// A version folder's name as numbers: `2026.10.19-6bbf2c4` -> 2026, 10, 19. nil for any other name.
    struct VersionName: Comparable {
        var year: Int
        var month: Int
        var day: Int

        init?(_ name: String) {
            let halves = name.split(separator: "-", omittingEmptySubsequences: false)
            guard halves.count == 2, !halves[1].isEmpty,
                  halves[1].allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) })
            else { return nil }
            let date = halves[0].split(separator: ".", omittingEmptySubsequences: false)
            guard date.count == 3, date[0].count == 4, (1...2).contains(date[1].count), (1...2).contains(date[2].count),
                  date.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let year = Int(date[0]), let month = Int(date[1]), let day = Int(date[2])
            else { return nil }
            (self.year, self.month, self.day) = (year, month, day)
        }

        static func < (lhs: VersionName, rhs: VersionName) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }
    }

    /// The folder's modification time (lstat); 0 when it can't be read.
    static func modificationDate(_ path: String) -> Double {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        return Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
    }

    /// Why a version folder must stay because of its `.running` folder; nil when it has none, or one that lists
    /// only processes that have ended.
    static func runningMarker(_ folder: String, isAlive: (Int32) -> Bool) -> String? {
        let marker = folder + "/.running"
        switch PathPresence.of(marker) {
        case .missing: return nil
        case .unknown(let why): return "its .running marker can't be looked at (\(why))"
        case .present: break
        }
        guard DirectoryEntries.kind(ofItemAt: marker) == .directory, let entries = DirectoryEntries.read(marker) else {
            return "its .running marker isn't a readable folder"
        }
        for entry in entries.sorted(by: { $0.name < $1.name }) {
            guard let pid = Int32(entry.name), pid > 0 else { return "its .running folder holds \(entry.name)" }
            if isAlive(pid) { return "process \(pid) is using it" }
        }
        return nil
    }

    /// True when a process with this id exists (also one this user may not signal).
    static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
