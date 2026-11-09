import Foundation

/// Which of Cursor's agent command-line versions may go (PLAN §4.6): every folder in `versions/` except the one
/// `.local/bin/cursor-agent` resolves into and the newest by name. A link that is missing, dangling or resolving
/// anywhere but into a version folder refuses the whole entry.
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
        // Only real folders are versions; links, files and hidden names are left alone.
        let folders = listing.filter { $0.kind == .directory && !$0.name.hasPrefix(".") }.map(\.name)
        guard folders.contains(inUse) else {
            return .refused("the cursor-agent link points into \(inUse), which is not a version folder")
        }
        let newest = folders.max { $0.compare($1, options: .numeric) == .orderedAscending } ?? inUse

        var kept: [Kept] = []
        var removable: [String] = []
        for name in folders.sorted(by: { $0.compare($1, options: .numeric) == .orderedAscending }) {
            var reasons: [String] = []
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
        return .resolved(CursorAgentVersions(removable: removable, kept: kept))
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
