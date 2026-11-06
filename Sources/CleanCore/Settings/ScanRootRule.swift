import Foundation

/// Which folders may be a saved scan root (PLAN §3, "Scan roots in settings"): only a folder strictly
/// inside the home folder or strictly inside `/Volumes/<name>/`, judged after symlinks are resolved.
///
/// A broader root would make light clean and removal reach checkouts that are not the user's projects:
/// `/opt/homebrew` is a git checkout whose `/*` ignore rule makes `lib/node_modules` look deletable.
/// `Settings` applies the rule to a settings file's roots, `SettingsModel` to a folder being added. Explicit
/// roots (`--root`, `CLEAN_CLAUDE_SCAN_ROOTS`) are not checked: the person typed them for one run.
public struct ScanRootRule: Sendable {
    /// Why a folder is not accepted, in words for the person; `path` is the folder as it was written.
    public struct Refusal: Error, Sendable, Hashable, CustomStringConvertible {
        public var path: String
        public var reason: String

        public var description: String { "\(path): \(reason)" }
    }

    public var home: URL

    public init(home: URL) {
        self.home = home
    }

    /// The folder in canonical form (symlinks resolved), or why it is refused.
    public func accept(_ folder: URL) -> Result<URL, Refusal> {
        let written = folder.standardizedFileURL.path
        let path = CanonicalPath.resolve(folder)
        let homePath = CanonicalPath.resolve(home)
        let leadsTo = path == written ? "" : " (it leads to \(path))"

        func refuse(_ reason: String) -> Result<URL, Refusal> {
            .failure(Refusal(path: written, reason: reason + leadsTo))
        }
        if path == "/" {
            return refuse("that is the whole disk")
        }
        if path == homePath {
            return refuse("that is the home folder itself; pick a folder inside it")
        }
        if homePath.hasPrefix(path + "/") {
            return refuse("it contains the home folder")
        }
        if path.hasPrefix(homePath + "/") {
            return .success(URL(fileURLWithPath: path, isDirectory: true))
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.first == "Volumes" {
            guard parts.count > 2 else { return refuse("that is a volume's root; pick a folder inside it") }
            return .success(URL(fileURLWithPath: path, isDirectory: true))
        }
        return refuse(
            "it is outside the home folder and the external volumes (a system folder, for one). "
                + "A scan root must be a folder inside \(homePath) or inside /Volumes/<name>/"
        )
    }

    /// The canonical folder, or nil when it is refused.
    public func canonical(_ folder: URL) -> URL? {
        try? accept(folder).get()
    }
}
