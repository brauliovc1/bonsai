import Foundation

public struct MergeCheck: Sendable, Codable, Equatable {
    public enum State: String, Sendable, Codable { case clean, conflicts, unavailable }
    public let state: State
    public let files: [String]
    public let detail: String?
    public let treeSHA: String?

    public init(state: State, files: [String] = [], detail: String? = nil, treeSHA: String? = nil) {
        self.state = state; self.files = files; self.detail = detail; self.treeSHA = treeSHA
    }

    public func message(base: String) -> String {
        switch state {
        case .clean: "Merges cleanly into \(base)"
        case .conflicts: "Conflicts in \(files.count) \(files.count == 1 ? "file" : "files")"
        case .unavailable: "Can't check"
        }
    }

    /// `git merge-tree` may write objects and run configured merge drivers. GitReadOnly's temporary
    /// metadata view has no drivers and sends every object write to its own disposable objects folder.
    public static func check(base: String, compare: String, using git: GitReadOnly) async -> MergeCheck {
        do {
            let result = try await git.result(["merge-tree", "--write-tree", "--name-only", "--messages", "-z", base, compare])
            let first = String(decoding: result.stdout.split(separator: 0).first ?? Data.SubSequence(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tree = [40, 64].contains(first.count) && first.allSatisfy(\.isHexDigit) ? first : nil
            if result.succeeded { return MergeCheck(state: .clean, treeSHA: tree) }
            if result.exitCode == 1, !result.timedOut {
                let fields = result.stdout.split(separator: 0, omittingEmptySubsequences: false)
                let files = fields.dropFirst().prefix(while: { !$0.isEmpty }).map { String(decoding: $0, as: UTF8.self) }
                if !files.isEmpty { return MergeCheck(state: .conflicts, files: files, treeSHA: tree) }
            }
            let message = result.timedOut ? "Git took too long. Refresh to try again." : result.stderr
            return MergeCheck(state: .unavailable, detail: message.isEmpty ? "Git 2.38 or newer is needed to check merges." : message)
        } catch { return MergeCheck(state: .unavailable, detail: String(describing: error)) }
    }
}
