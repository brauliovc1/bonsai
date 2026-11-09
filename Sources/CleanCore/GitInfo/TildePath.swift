import Foundation

/// Paths shortened for display: the home folder becomes "~".
public enum TildePath {
    /// `/Users/me/Documents/GitHub/app` -> `~/Documents/GitHub/app`; `home` itself -> `~`; anything outside
    /// the home folder is unchanged. Lexical, so the characters stay exactly as given.
    public static func abbreviate(_ path: String, home: URL) -> String {
        let homePath = Worktree.standardize(home.path)
        guard homePath != "/" else { return path }
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
