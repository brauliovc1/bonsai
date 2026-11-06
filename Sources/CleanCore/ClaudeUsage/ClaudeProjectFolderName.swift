import Foundation

/// How Claude names the folders under `<claude config>/projects` (PLAN §4.3), for the usage report:
/// encoding is `TranscriptFolderEncoding` (the one implementation, shared with the idle clock); this adds
/// the reverse lookup.
public enum ClaudeProjectFolderName {
    public static func encode(_ path: String) -> String {
        TranscriptFolderEncoding.encode(path)
    }

    /// Folder name -> path, for every candidate path that encodes to it. A name that two different
    /// candidates encode to (`/a/b-c` and `/a/b/c`) is left out: guessing would put a wrong path on
    /// screen, so those folders keep their raw name.
    public static func decodingTable(candidates: [String]) -> [String: String] {
        var pathsByName: [String: Set<String>] = [:]
        for path in candidates {
            pathsByName[encode(path), default: []].insert(path)
        }
        return pathsByName.compactMapValues { paths in
            paths.count == 1 ? paths.first : nil
        }
    }
}
