import CleanCore
import Foundation

/// Paths as the CLI prints them: relative to the most specific scan root that contains them, otherwise
/// absolute with `~` for the home folder.
struct PathDisplay {
    let roots: [URL]
    let home: URL

    func string(_ url: URL) -> String {
        let relative = roots
            .compactMap { CanonicalPath.relativePath(of: url, to: $0) }
            .min { $0.count < $1.count }
        if let relative { return relative }
        return homeRelative(url)
    }

    func string(_ path: String) -> String {
        string(URL(fileURLWithPath: path))
    }

    /// `~/...` when under the home folder, else the absolute path.
    func homeRelative(_ url: URL) -> String {
        if let underHome = CanonicalPath.relativePath(of: url, to: home), underHome != "." {
            return "~/" + underHome
        }
        return url.path
    }
}
