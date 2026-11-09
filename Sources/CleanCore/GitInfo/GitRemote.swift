import Foundation

/// One remote of a repo, from `git remote -v`, its URLs already without credentials (`RemoteURL.redacted`).
public struct GitRemote: Sendable, Codable, Hashable {
    public var name: String
    public var url: String
    /// Only when it differs from `url`.
    public var pushURL: String?

    public init(name: String, url: String, pushURL: String? = nil) {
        self.name = name
        self.url = RemoteURL.redacted(url)
        self.pushURL = pushURL.map(RemoteURL.redacted).flatMap { $0 == self.url ? nil : $0 }
    }

    /// The remotes in `git remote -v` output (`<name>\t<url> (fetch)` and `(push)` lines), in order.
    static func parse(_ output: String) -> [GitRemote] {
        var order: [String] = []
        var fetch: [String: String] = [:]
        var push: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let name = String(line[..<tab])
            var rest = line[line.index(after: tab)...]
            let isPush: Bool
            if rest.hasSuffix(" (push)") {
                isPush = true
                rest = rest.dropLast(7)
            } else if rest.hasSuffix(" (fetch)") {
                isPush = false
                rest = rest.dropLast(8)
            } else {
                continue
            }
            guard !name.isEmpty, !rest.isEmpty else { continue }
            if fetch[name] == nil, push[name] == nil { order.append(name) }
            if isPush { push[name] = String(rest) } else { fetch[name] = String(rest) }
        }
        return order.compactMap { name in
            guard let url = fetch[name] ?? push[name] else { return nil }
            return GitRemote(name: name, url: url, pushURL: push[name])
        }
    }

    /// "origin" first, then the others in git's order.
    static func preferredOrder(_ remotes: [GitRemote]) -> [GitRemote] {
        remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
    }
}
