import Foundation

/// The PLAN §4.4 rules for one DerivedData folder. `DerivedDataScanner` uses them to list, and
/// `DerivedDataCleaner` again right before deleting. Read-only.
///
/// Orphaned only when `info.plist` has an absolute `WorkspacePath`, that path is not under `/var/folders`
/// or `/private/var/folders`, and lstat says it does not exist (`ENOENT`/`ENOTDIR`; a path that can't be
/// looked at is unreadable, not missing).
struct DerivedDataClassifier: Sendable {
    static let xcodeInternalPrefixes = ["/var/folders", "/private/var/folders"]

    /// Test seam: test fixtures live under `/var/folders` themselves.
    var internalPrefixes = DerivedDataClassifier.xcodeInternalPrefixes

    struct Classification: Sendable, Hashable {
        var state: DerivedDataState
        var workspacePath: String?
        var detail: String?
    }

    func classify(_ folder: URL) -> Classification {
        let plist = folder.appending(path: "info.plist")
        switch PathPresence.of(plist.path) {
        case .missing: return Classification(state: .noInfoPlist)
        case .unknown(let why): return Classification(state: .unreadable, detail: "info.plist can't be checked: \(why)")
        case .present: break
        }
        guard let data = try? Data(contentsOf: plist) else {
            return Classification(state: .unreadable, detail: "info.plist can't be read")
        }
        guard let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return Classification(state: .unreadable, detail: "info.plist is not a property list dictionary")
        }
        guard let workspace = dictionary["WorkspacePath"] as? String, !workspace.isEmpty else {
            return Classification(state: .unreadable, detail: "info.plist has no WorkspacePath")
        }
        guard workspace.hasPrefix("/") else {
            return Classification(state: .unreadable, workspacePath: workspace, detail: "WorkspacePath is not an absolute path")
        }
        if isXcodeInternal(workspace) { return Classification(state: .xcodeInternal, workspacePath: workspace) }
        switch PathPresence.of(workspace) {
        case .present:
            return Classification(state: .live, workspacePath: workspace)
        case .missing:
            return Classification(state: .orphaned, workspacePath: workspace)
        case .unknown(let why):
            return Classification(state: .unreadable, workspacePath: workspace, detail: "the project path can't be checked: \(why)")
        }
    }

    /// Under one of the internal prefixes, after removing `.` and `..` lexically.
    func isXcodeInternal(_ path: String) -> Bool {
        let standardized = Worktree.standardize(path)
        return internalPrefixes.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }
}
