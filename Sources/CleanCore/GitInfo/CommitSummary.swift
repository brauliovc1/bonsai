import Foundation

/// One commit as `git log` shows it: what the Worktrees screen and `scan --json` say about a worktree's
/// last commit, and the details panel's recent commits.
public struct CommitSummary: Sendable, Codable, Hashable {
    /// The full hash.
    public var sha: String
    /// The first paragraph of the message on one line (git's `%s`).
    public var subject: String
    /// The whole message, trailing whitespace trimmed.
    public var message: String
    public var author: String
    /// The committer date, the one the idle clock counts from (PLAN §4.3, signal 1).
    public var date: Date

    public init(sha: String, subject: String, message: String, author: String, date: Date) {
        self.sha = sha
        self.subject = subject
        self.message = message
        self.author = author
        self.date = date
    }

    /// The first 8 characters of the hash, as the rest of the app shows detached HEADs.
    public var shortSHA: String { String(sha.prefix(8)) }

    /// `git log` arguments that print commits in the form `parse` reads: NUL between commits, the unit
    /// separator (0x1F) between fields, the message last so nothing in it can shift a field.
    static let logArguments = ["log", "-z", "--format=%H%x1f%an%x1f%ct%x1f%s%x1f%B"]

    /// The commits of `git log -z --format=%H%x1f%an%x1f%ct%x1f%s%x1f%B`, in output order. Records that
    /// don't have the five fields, a hash or a date are skipped.
    static func parse(_ output: Data) -> [CommitSummary] {
        output.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: 0x1F, maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5 else { return nil }
            func text(_ index: Int) -> String {
                String(decoding: fields[index], as: UTF8.self)
            }
            let sha = text(0).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isHash(sha), let seconds = TimeInterval(text(2)) else { return nil }
            return CommitSummary(
                sha: sha,
                subject: text(3),
                message: text(4).trimmingCharacters(in: .whitespacesAndNewlines),
                author: text(1),
                date: Date(timeIntervalSince1970: seconds)
            )
        }
    }

    /// 4 to 64 lowercase hex digits: what `git worktree list` prints as HEAD, and the only thing passed to
    /// `git log` as a revision (never an option, never a path).
    static func isHash(_ text: String) -> Bool {
        (4...64).contains(text.utf8.count) && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
