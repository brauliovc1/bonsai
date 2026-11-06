/// A git version as printed by `git --version`, e.g. `git version 2.54.0 (Apple Git-157)`.
public struct GitVersion: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    /// `git worktree list --porcelain -z` needs git 2.36.
    public static let minimumSupported = GitVersion(major: 2, minor: 36, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the output of `git --version`. Returns nil when no version number is found.
    public init?(parsing output: String) {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard let versionWord = words.first(where: { $0.first?.isNumber == true }) else { return nil }
        let numbers = versionWord.split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber))
        }
        guard let major = numbers.first ?? nil else { return nil }
        let minor = numbers.count > 1 ? numbers[1] ?? 0 : 0
        let patch = numbers.count > 2 ? numbers[2] ?? 0 : 0
        self.init(major: major, minor: minor, patch: patch)
    }

    public var isSupported: Bool { self >= Self.minimumSupported }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
