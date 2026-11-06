import Foundation

/// Lists the folders of one DerivedData root with their state (PLAN §4.4) and size. Read-only.
public struct DerivedDataScanner: Sendable {
    public var root: URL
    /// For size estimates; nil = no sizes.
    public var du: URL?
    var classifier = DerivedDataClassifier()

    public init(root: URL, du: URL?) {
        self.root = root
        self.du = du
    }

    /// The root from `DerivedDataLocator`, `du` from the environment. The locator's note becomes a warning.
    public static func scan(environment: CleanEnvironment, runner: CommandRunner = .live) async -> DerivedDataReport {
        let location = await DerivedDataLocator(environment: environment, runner: runner).locate()
        var report = await DerivedDataScanner(root: location.root, du: environment.tools.du).scan()
        if let note = location.note { report.warnings.insert(note, at: 0) }
        return report
    }

    public func scan() async -> DerivedDataReport {
        guard let listing = DirectoryEntries.read(root.path) else {
            if PathPresence.of(root.path) == .missing {
                return DerivedDataReport(root: root.path, rootExists: false)
            }
            return DerivedDataReport(root: root.path, rootExists: true, warnings: ["cannot read \(root.path)"])
        }
        // Symlinks and files are never entries: nothing outside a real folder of the root is touched.
        let names = listing.filter { $0.kind == .directory }.map(\.name).sorted()
        let urls = names.map { root.appending(path: $0, directoryHint: .isDirectory) }
        let classifications = urls.map(classifier.classify)

        var warnings: [String] = []
        var sizes: [String: Int64] = [:]
        if let du, !urls.isEmpty {
            let measured = await DirectorySizer(du: du).sizes(of: urls)
            sizes = measured.sizes
            warnings += measured.issues.map(\.description)
        }

        let entries = zip(names, zip(urls, classifications)).map { name, item in
            let (url, classification) = item
            let bytes = sizes[url.path]
            var orphan: OrphanedDerivedData?
            if classification.state == .orphaned, let workspace = classification.workspacePath {
                orphan = OrphanedDerivedData(root: root.path, name: name, workspacePath: workspace, bytes: bytes)
            }
            return DerivedDataEntry(
                folder: root.path + "/" + name,
                name: name,
                workspacePath: classification.workspacePath,
                state: classification.state,
                detail: classification.detail,
                bytes: bytes,
                orphan: orphan
            )
        }
        return DerivedDataReport(root: root.path, rootExists: true, entries: entries, warnings: warnings)
    }
}
