import Foundation

public enum CompareSelection: Sendable, Hashable, Codable {
    case ref(String)
    case worktree(String)

    public var label: String {
        switch self { case .ref(let ref): ref; case .worktree(let path): URL(fileURLWithPath: path).lastPathComponent + " (worktree)" }
    }
}

public struct CompareCommit: Sendable, Hashable, Codable, Identifiable {
    public let sha: String
    public let subject: String
    public let author: String
    public let date: Date
    public var id: String { sha }
}

public struct CompareRange: Sendable, Codable {
    public let base: String
    public let compare: CompareSelection
    public let baseSHA: String
    public let compareSHA: String
    public let mergeBase: String
    public let ahead: Int
    public let behind: Int
    public let commits: [CompareCommit]
}

public struct CompareFile: Sendable, Codable, Hashable, Identifiable {
    public enum Status: String, Sendable, Codable { case added, modified, deleted, renamed, copied, typeChanged, unmerged }
    public var path: String
    public var oldPath: String?
    public var status: Status
    public var additions: Int
    public var deletions: Int
    public var isBinary: Bool
    public var similarity: Int?
    public var oldMode: String?
    public var newMode: String?
    public var notCommitted: Bool = false
    public var oldBytes: Int?
    public var newBytes: Int?
    public var id: String { path }
    public var modeChanged: Bool { status != .added && status != .deleted && oldMode != nil && newMode != nil && oldMode != newMode }
    public var isGenerated: Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "pubspec.lock", "Podfile.lock", "Package.resolved"].contains(name)
            || [".g.dart", ".freezed.dart", ".pbxproj", ".min.js"].contains { name.hasSuffix($0) }
    }
    public var isLarge: Bool { additions + deletions > 3_000 || max(oldBytes ?? 0, newBytes ?? 0) > 1_000_000 }
}

public struct CompareSnapshot: Sendable, Codable {
    public let range: CompareRange
    public let files: [CompareFile]
    public let merge: MergeCheck
    public var additions: Int { files.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    private enum CodingKeys: String, CodingKey { case range, files, merge, additions, deletions, summary }
    public init(range: CompareRange, files: [CompareFile], merge: MergeCheck) {
        self.range = range; self.files = files; self.merge = merge
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(CompareRange.self, forKey: .range)
        files = try container.decode([CompareFile].self, forKey: .files)
        merge = try container.decode(MergeCheck.self, forKey: .merge)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(range, forKey: .range); try container.encode(files, forKey: .files)
        try container.encode(merge, forKey: .merge); try container.encode(additions, forKey: .additions)
        try container.encode(deletions, forKey: .deletions); try container.encode(summary, forKey: .summary)
    }
    public var summary: String {
        "\(range.commits.count) commits · \(files.count) files · +\(additions) −\(deletions)\n\(range.ahead) ahead, \(range.behind) behind \(range.base)\n\(merge.message(base: range.base))"
    }
}
