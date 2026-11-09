import Foundation

/// Whether git ignores a folder and tracks nothing in it (PLAN §4.2), asked from the folder's parent with the
/// folder's name: run inside the folder, git would apply the folder's own `.gitignore` to the folder itself.
/// Light clean asks it for each candidate; the package-copy rule (§4.1) for the build folder around a copy.
///
/// The names asked about are §4.2 names, which are ASCII, so they reach git unchanged; the parent's path only
/// goes to `-C` (a chdir, which matches names whatever their Unicode form). `ls-files` matches the name
/// case-insensitively (`:(icase)`, APFS is case-insensitive) and is asked first: git calls a folder with
/// tracked files in it "not ignored".
struct IgnoredOutputCheck: Sendable {
    var git: Git

    /// nil when git, answering for `worktree`, ignores `parent/name` and tracks nothing in it. A git failure
    /// is a reason too.
    func reason(name: String, parent: URL, worktree: URL) async -> LightCleanSkipReason? {
        do {
            // git must answer for this worktree, not for a repo around it (a broken `.git` file).
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: parent)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), worktree) else {
                return .gitError("git sees \(topLevel) here, not this worktree")
            }
            if !(try await git.git(["ls-files", "-z", "--", ":(icase)\(name)"], in: parent)).isEmpty { return .hasTrackedFiles }
            let ignore = try await git.result(["check-ignore", "-q", "--", name], in: parent)
            if ignore.timedOut { return .gitError("git check-ignore timed out") }
            switch ignore.exitCode {
            case 0: return nil
            case 1: return .notIgnored
            default:
                let message = ignore.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .gitError("git check-ignore failed (exit \(ignore.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
            }
        } catch {
            return .gitError("\(error)")
        }
    }
}
