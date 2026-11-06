import Foundation

/// Works out how long a worktree has been idle from the four signals of PLAN §4.3.
public struct IdleClock: Sendable {
    public var git: Git
    public var transcripts: ClaudeTranscriptLocator
    public var fileWalk: FileActivityWalk
    public var now: @Sendable () -> Date

    public init(
        git: Git,
        claudeConfigDirectory: URL,
        maxEntries: Int = FileActivityWalk.defaultMaxEntries,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.git = git
        self.transcripts = ClaudeTranscriptLocator(claudeConfigDirectory: claudeConfigDirectory)
        self.fileWalk = FileActivityWalk(maxEntries: maxEntries)
        self.now = now
    }

    public func report(for worktree: Worktree) async -> IdleReport {
        let folder = worktree.url
        var signals: [IdleSignal: Date] = [:]
        var errors: [String] = []

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            return IdleReport.make(signals: [:], capHit: false, errors: ["folder missing"], now: now())
        }

        do {
            let seconds = try await git.gitString(["log", "-1", "--format=%ct"], in: folder)
            guard let value = TimeInterval(seconds) else { throw ParseError(output: seconds) }
            signals[.headCommit] = Date(timeIntervalSince1970: value)
        } catch {
            errors.append("last commit: \(error)")
        }

        do {
            if let date = try await gitActivity(in: folder) { signals[.gitActivity] = date }
        } catch {
            errors.append("git activity: \(error)")
        }

        let walk = fileWalk.walk(folder)
        if let newest = walk.newest { signals[.fileChange] = newest }
        errors += walk.errors

        switch transcripts.lookup(for: worktree.path) {
        case .newest(let date): signals[.claudeTranscript] = date
        case .unreadable(let why): errors.append("Claude transcripts: \(why)")
        case .absent, .empty: break
        }

        return IdleReport.make(signals: signals, capHit: walk.capHit, errors: errors, now: now())
    }

    /// Newest of: the mtimes of `index` and `HEAD` in the worktree's own git dir, and the time of the last
    /// entry in its `logs/HEAD`. Not that file's mtime: `git gc` rewrites (or empties) every reflog of a repo.
    private func gitActivity(in folder: URL) async throws -> Date? {
        let gitDir = URL(fileURLWithPath: try await git.gitString(["rev-parse", "--absolute-git-dir"], in: folder))
        var dates = ["index", "HEAD"].compactMap { name -> Date? in
            let attributes = try? FileManager.default.attributesOfItem(atPath: gitDir.appending(path: name).path)
            return attributes?[.modificationDate] as? Date
        }
        if let last = try Self.lastReflogDate(gitDir.appending(path: "logs/HEAD")) { dates.append(last) }
        return dates.max()
    }

    /// The timestamp of the last entry of a reflog (`<old> <new> <name> <<email>> <seconds> <zone>\t<message>`),
    /// reading only the end of the file. nil when the file is missing or empty.
    static func lastReflogDate(_ file: URL) throws -> Date? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let tail = min(size, 65_536)
        try handle.seek(toOffset: size - tail)
        let data = try handle.read(upToCount: Int(tail)) ?? Data()
        guard let line = data.split(separator: UInt8(ascii: "\n")).last(where: { !$0.isEmpty }) else { return nil }
        let header = line.split(separator: UInt8(ascii: "\t"), maxSplits: 1).first ?? line
        let words = header.split(separator: UInt8(ascii: " "))
        guard words.count >= 2, let seconds = TimeInterval(String(decoding: words[words.count - 2], as: UTF8.self)) else {
            throw ParseError(output: String(decoding: line.prefix(200), as: UTF8.self))
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private struct ParseError: Error, CustomStringConvertible {
        var output: String
        var description: String { "unexpected output \"\(output)\"" }
    }
}
