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

    /// The absolute path with every character outside `[A-Za-z0-9]` replaced by `-`.
    public static func encode(_ path: String) -> String {
        String(path.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9": Character(scalar)
            default: "-"
            }
        })
    }

    /// Transcript folders that exist for `folder`. Both the path as given and its symlink-resolved form
    /// are tried (`/var/...` vs `/private/var/...`).
    public func transcriptFolders(for folder: URL) -> [URL] {
        let spellings = [folder.standardized.path, CanonicalPath.resolve(folder)]
        var seen: Set<String> = []
        return spellings.compactMap { path in
            let encoded = Self.encode(path)
            guard seen.insert(encoded).inserted else { return nil }
            let candidate = projectsDirectory.appending(path: encoded, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return candidate
        }
    }

    /// The newest modification date of a `*.jsonl` file directly inside the transcript folder(s), or nil.
    public func newestTranscriptDate(for folder: URL) -> Date? {
        var newest: Date?
        for directory in transcriptFolders(for: folder) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let date = values.contentModificationDate
                else { continue }
                if newest.map({ date > $0 }) ?? true { newest = date }
            }
        }
        return newest
    }
}
