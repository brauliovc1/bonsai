import Foundation

/// A branch's upstream and how far apart they are, as of the last fetch (clean-claude never fetches).
public struct UpstreamStatus: Sendable, Codable, Hashable {
    /// "origin/feature".
    public var name: String
    public var ahead: Int
    public var behind: Int
    /// The upstream is configured but its remote-tracking branch no longer exists.
    public var isGone: Bool

    public init(name: String, ahead: Int = 0, behind: Int = 0, isGone: Bool = false) {
        self.name = name
        self.ahead = ahead
        self.behind = behind
        self.isGone = isGone
    }

    /// From one line of `git for-each-ref --format=%(upstream:short)%x1f%(upstream:track,nobracket)`:
    /// track is "", "ahead 2", "behind 1", "ahead 2, behind 1" or "gone". nil without an upstream.
    static func parse(upstream: String, track: String) -> UpstreamStatus? {
        guard !upstream.isEmpty else { return nil }
        var status = UpstreamStatus(name: upstream)
        for part in track.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let words = part.split(separator: " ")
            if part == "gone" {
                status.isGone = true
            } else if words.count == 2, let count = Int(words[1]) {
                if words[0] == "ahead" { status.ahead = count }
                if words[0] == "behind" { status.behind = count }
            }
        }
        return status
    }
}
