import Foundation

enum HomePath {
    /// `/Users/me/Library/x` -> `~/Library/x`; paths outside the home folder are unchanged.
    static func abbreviate(_ path: String, home: URL) -> String {
        let homePath = home.standardized.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
