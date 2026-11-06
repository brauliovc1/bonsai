import CleanCore
import Foundation

/// The demo world `fixture-world` builds and the app-model tests scan: three repos with bare remotes and
/// one linked worktree for each status the app shows (PLAN §4.1), each aged so the idle clock (§4.3) sees
/// the intended number of days.
///
/// ```
/// <folder>/
///   home/      HOME for the fixture's git
///   remotes/   bare remotes (atlas, beacon, cobalt, and the two nested packages)
///   root/      atlas, beacon, cobalt and their sibling worktrees
/// ```
public struct DemoWorld: Sendable {
    public let fixture: GitFixture
    public let repos: [URL]
    public let items: [Item]

    /// The folder to point the app and the CLI at.
    public var folder: URL { fixture.url }

    /// One linked worktree and what it was built to be.
    public struct Item: Sendable {
        public var url: URL
        public var repo: URL
        /// What it shows, for the printout.
        public var purpose: String
        /// Days the idle clock should report; nil when it can't know (the folder is gone).
        public var idleDays: Int?
        /// The expected `WorktreeStatus.label`: exact for "AUTO-READY" and "SAFE", a prefix otherwise
        /// ("BLOCKED: uncommitted" matches "BLOCKED: uncommitted (2)").
        public var status: String
        /// Label prefixes that must be among the verdict's notes.
        public var notes: [String]

        public init(url: URL, repo: URL, purpose: String, idleDays: Int?, status: String, notes: [String] = []) {
            self.url = url
            self.repo = repo
            self.purpose = purpose
            self.idleDays = idleDays
            self.status = status
            self.notes = notes
        }

        /// Why `assessment` is not what this item was built to be; nil when it is.
        public func mismatch(_ assessment: WorktreeAssessment) -> String? {
            var problems: [String] = []
            let label = assessment.status.label
            let exact = status == "AUTO-READY" || status == "SAFE"
            if exact ? label != status : !label.hasPrefix(status) {
                problems.append("status \(label), expected \(status)")
            }
            if assessment.idle.idleDays != idleDays {
                let found = assessment.idle.idleDays.map { "\($0)d" } ?? "unknown"
                problems.append("idle \(found), expected \(idleDays.map { "\($0)d" } ?? "unknown")")
            }
            for note in notes where !assessment.safety.notes.contains(where: { $0.label.hasPrefix(note) }) {
                problems.append("note \"\(note)\" missing")
            }
            return problems.isEmpty ? nil : problems.joined(separator: "; ")
        }
    }

    /// Builds the world in `folder` (inside the temp dir; kept afterwards), or in a fresh fixture that is
    /// removed with it. `now` is the moment the ages count back from.
    public static func build(in folder: URL? = nil, now: Date = Date()) async throws -> DemoWorld {
        let fixture = try folder.map { try GitFixture(keeping: $0) } ?? GitFixture()
        let builder = DemoWorldBuilder(fixture: fixture, now: now)
        let (repos, items) = try await builder.build()
        return DemoWorld(fixture: fixture, repos: repos, items: items)
    }

    public func remove() {
        fixture.remove()
    }

    /// Why `folder` can't hold a demo world, or nil when it can: it must be inside the system temporary
    /// directory, and be missing or an empty folder (a `.DS_Store` is fine). A folder whose contents can't be
    /// listed is refused, not taken for empty.
    public static func problem(withTarget folder: URL) -> String? {
        let temp = FileManager.default.temporaryDirectory.path
        guard TemporaryDirectory.isDisposable(folder) else {
            return "\(folder.path) is not inside \(temp); fixture-world only builds there"
        }
        guard (try? FileManager.default.attributesOfItem(atPath: folder.path)) != nil else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "\(folder.path) exists and is not a folder"
        }
        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            return "\(folder.path) can't be listed: \(error.localizedDescription)"
        }
        guard contents.allSatisfy({ $0 == ".DS_Store" }) else { return "\(folder.path) is not empty" }
        return nil
    }

    public func item(named name: String) -> Item? {
        items.first { $0.url.lastPathComponent == name }
    }

    /// The item built at the same place as `worktree`.
    public func item(for worktree: Worktree) -> Item? {
        items.first { CanonicalPath.same($0.url, worktree.url) }
    }

    /// `path` relative to the world folder, for printing.
    public func relativePath(_ url: URL) -> String {
        CanonicalPath.relativePath(of: url, to: folder) ?? url.path
    }
}
