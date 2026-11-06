/// Something that went wrong for one root, folder, repo or worktree. Issues never fail a whole scan.
public struct ScanIssue: Sendable, Codable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable, Hashable {
        case noRoots
        case rootMissing
        case rootRefused
        case unreadableFolder
        case gitMissing
        case gitUnsupported
        case worktreeListFailed
        case duMissing
        case sizeFailed
    }

    public var kind: Kind
    /// The folder, repo or worktree the issue is about, when there is one.
    public var path: String?
    public var message: String

    public init(kind: Kind, path: String? = nil, message: String) {
        self.kind = kind
        self.path = path
        self.message = message
    }

    public var description: String {
        guard let path else { return message }
        return "\(path): \(message)"
    }
}
