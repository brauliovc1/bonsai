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

        if let transcript = transcripts.newestTranscriptDate(for: folder) {
            signals[.claudeTranscript] = transcript
        }

        return IdleReport.make(signals: signals, capHit: walk.capHit, errors: errors, now: now())
    }

    /// Newest mtime of `index`, `HEAD` and `logs/HEAD` in the worktree's own git dir.
    private func gitActivity(in folder: URL) async throws -> Date? {
        let gitDirOutput = try await git.gitString(["rev-parse", "--git-dir"], in: folder)
        let gitDir = gitDirOutput.hasPrefix("/")
            ? URL(fileURLWithPath: gitDirOutput, isDirectory: true)
            : folder.appending(path: gitDirOutput, directoryHint: .isDirectory)
        let dates = ["index", "HEAD", "logs/HEAD"].compactMap { name -> Date? in
            let attributes = try? FileManager.default.attributesOfItem(atPath: gitDir.appending(path: name).path)
            return attributes?[.modificationDate] as? Date
        }
        return dates.max()
    }

    private struct ParseError: Error, CustomStringConvertible {
        var output: String
        var description: String { "unexpected output \"\(output)\"" }
    }
}
