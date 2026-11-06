import Foundation

/// Parses the output of `git worktree list --porcelain -z`.
///
/// The format is a list of NUL-terminated attribute lines; an empty field ends a record:
/// `worktree <path>\0HEAD <sha>\0branch refs/heads/<name>\0\0`. Boolean attributes (`detached`, `bare`)
/// have no value; `locked` and `prunable` may carry a reason.
public enum WorktreeListParser {
    public struct Record: Sendable, Equatable {
        public var path: String
        public var head: String?
        /// Without `refs/heads/`.
        public var branch: String?
        public var isDetached: Bool
        public var isBare: Bool
        /// nil = not locked, "" = locked without a reason.
        public var lockedReason: String?
        public var prunableReason: String?

        public init(
            path: String,
            head: String? = nil,
            branch: String? = nil,
            isDetached: Bool = false,
            isBare: Bool = false,
            lockedReason: String? = nil,
            prunableReason: String? = nil
        ) {
            self.path = path
            self.head = head
            self.branch = branch
            self.isDetached = isDetached
            self.isBare = isBare
            self.lockedReason = lockedReason
            self.prunableReason = prunableReason
        }
    }

    /// Pure function over the bytes. Attributes before the first `worktree` line and unknown attributes are
    /// ignored; a last record without its terminating empty field is still returned.
    public static func parse(_ data: Data) -> [Record] {
        var records: [Record] = []
        var current: Record?

        for field in data.split(separator: 0, omittingEmptySubsequences: false) {
            guard !field.isEmpty else {
                if let record = current { records.append(record) }
                current = nil
                continue
            }
            let line = String(decoding: field, as: UTF8.self)
            let (key, value) = split(line)
            if key == "worktree" {
                if let record = current { records.append(record) }
                current = Record(path: value ?? "")
                continue
            }
            guard var record = current else { continue }
            switch key {
            case "HEAD": record.head = value
            case "branch": record.branch = value.map(shortBranch)
            case "detached": record.isDetached = true
            case "bare": record.isBare = true
            case "locked": record.lockedReason = value ?? ""
            case "prunable": record.prunableReason = value ?? ""
            default: break
            }
            current = record
        }
        if let record = current { records.append(record) }
        return records
    }

    private static func split(_ line: String) -> (key: String, value: String?) {
        guard let space = line.firstIndex(of: " ") else { return (line, nil) }
        return (String(line[..<space]), String(line[line.index(after: space)...]))
    }

    private static func shortBranch(_ ref: String) -> String {
        let prefix = "refs/heads/"
        return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
    }
}
