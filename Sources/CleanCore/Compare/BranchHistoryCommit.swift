import Foundation

/// Dates and parents are read from the immutable commit, while creation dates come from reflogs.
public struct BranchHistoryCommit: Sendable, Codable, Hashable, Identifiable {
    public let sha: String
    public let subject: String
    public let date: Date
    public let parents: [String]
    public var id: String { sha }
    public var shortSHA: String { String(sha.prefix(8)) }

    public init(sha: String, subject: String, date: Date, parents: [String] = []) {
        self.sha = sha; self.subject = subject; self.date = date; self.parents = parents
    }
}
