import Foundation

/// Finds the Claude Code transcripts for a folder: `<claude config>/projects/<encoded path>/*.jsonl`
/// (PLAN §4.3, signal 4). Read-only. The folder naming is not a documented format; when nothing matches,
/// the signal is simply absent.
public struct ClaudeTranscriptLocator: Sendable {
    public var claudeConfigDirectory: URL

    public init(claudeConfigDirectory: URL) {
        self.claudeConfigDirectory = claudeConfigDirectory
    }

    public var projectsDirectory: URL {
        claudeConfigDirectory.appending(path: "projects", directoryHint: .isDirectory)
    }

    /// What was found for one folder.
    public enum Lookup: Sendable, Equatable {
        /// No transcript folder: the signal is absent, not an error.
        case absent
        /// Transcript folders exist but hold no `*.jsonl`.
        case empty
        case newest(Date)
        /// A transcript folder exists but can't be read: idle unknown.
        case unreadable(String)
    }

    /// Transcript folders that exist for `path`. The path as git printed it and its symlink-resolved form
    /// (`/var/...` vs `/private/var/...`) are tried, each composed and decomposed, since the encoding works on
    /// UTF-16 code units and "é" is one unit composed but two decomposed.
    public func transcriptFolders(for path: String) -> [URL] {
        let resolved = CanonicalPath.resolve(path)
        let spellings = [path, resolved].flatMap { [$0, $0.precomposedStringWithCanonicalMapping, $0.decomposedStringWithCanonicalMapping] }
        var seen: Set<String> = []
        return spellings.compactMap { path in
            let encoded = TranscriptFolderEncoding.encode(path)
            guard seen.insert(encoded).inserted else { return nil }
            let candidate = projectsDirectory.appending(path: encoded, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return candidate
        }
    }

    /// The newest `*.jsonl` modification date directly inside the transcript folder(s) for `path`.
    public func lookup(for path: String) -> Lookup {
        let folders = transcriptFolders(for: path)
        guard !folders.isEmpty else { return .absent }
        var newest: Date?
        for directory in folders {
            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
                )
            } catch {
                return .unreadable("cannot read \(directory.path)")
            }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let date = values.contentModificationDate
                else { continue }
                if newest.map({ date > $0 }) ?? true { newest = date }
            }
        }
        return newest.map(Lookup.newest) ?? .empty
    }

    /// The newest transcript date, or nil (absent, empty or unreadable).
    public func newestTranscriptDate(for path: String) -> Date? {
        if case .newest(let date) = lookup(for: path) { return date }
        return nil
    }
}
