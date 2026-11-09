import Foundation

/// Remote URLs as clean-claude keeps and shows them. A remote can carry a credential
/// (`https://user:token@host/...`, `https://token@host/...`, `?access_token=...`), so every URL read from
/// git goes through `redacted` before it is stored, shown, logged or put in JSON.
public enum RemoteURL {
    /// The URL without user-info (user name, password or token), query or fragment:
    /// `https://me:ghp_x@github.com/me/app.git?t=1` -> `https://github.com/me/app.git`,
    /// `git@github.com:me/app.git` -> `github.com:me/app.git`. Local paths are unchanged.
    public static func redacted(_ url: String) -> String {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = text.range(of: "://") {
            let scheme = text[..<separator.lowerBound]
            var rest = text[separator.upperBound...]
            if let end = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<end] }
            let authorityEnd = rest.firstIndex(of: "/") ?? rest.endIndex
            if let at = rest[..<authorityEnd].lastIndex(of: "@") {
                rest = rest[rest.index(after: at)...]
            } else if hasNonNumericPort(rest[..<authorityEnd]), let at = rest.firstIndex(of: "@") {
                // "user:pa/ss@host": a raw "/" in a password ends the authority early; drop through the "@".
                rest = rest[rest.index(after: at)...]
            }
            return scheme + "://" + rest
        }
        guard isSCPLike(text) else { return text }
        // [user[:password]@]host:path: everything up to the last "@" before the path's first "/".
        let pathStart = text.firstIndex(of: "/") ?? text.endIndex
        guard let at = text[..<pathStart].lastIndex(of: "@") else { return text }
        return String(text[text.index(after: at)...])
    }

    /// Host and path without scheme, user-info, port or ".git" (`github.com/me/app`); local paths with "~"
    /// for `home` (`~/remotes/app.git`).
    public static func short(_ url: String, home: URL? = nil) -> String {
        let clean = redacted(url)
        if let separator = clean.range(of: "://") {
            let scheme = clean[..<separator.lowerBound].lowercased()
            let rest = String(clean[separator.upperBound...])
            if scheme == "file" { return localPath(rest, home: home) }
            let authorityEnd = rest.firstIndex(of: "/") ?? rest.endIndex
            var host = rest[..<authorityEnd]
            // A port ("host:2222"), but not the colons of an IPv6 address ("[::1]").
            if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]"),
               host[host.index(after: colon)...].allSatisfy(\.isNumber) {
                host = host[..<colon]
            }
            return trimmed(String(host) + rest[authorityEnd...])
        }
        guard isSCPLike(clean), let colon = clean.firstIndex(of: ":") else { return localPath(clean, home: home) }
        var path = clean[clean.index(after: colon)...]
        while path.hasPrefix("/") { path = path.dropFirst() }
        return trimmed(clean[..<colon] + "/" + path)
    }

    /// git's rule for the scp-like form: a ":" before any "/", and not a local path.
    static func isSCPLike(_ text: String) -> Bool {
        guard !text.hasPrefix("/"), !text.hasPrefix("."), !text.hasPrefix("~"),
              let colon = text.firstIndex(of: ":") else { return false }
        return !text[..<colon].contains("/")
    }

    private static func hasNonNumericPort(_ authority: Substring) -> Bool {
        guard let colon = authority.lastIndex(of: ":") else { return false }
        let port = authority[authority.index(after: colon)...]
        return !port.isEmpty && !port.allSatisfy(\.isNumber)
    }

    private static func localPath(_ path: String, home: URL?) -> String {
        guard let home else { return path }
        return TildePath.abbreviate(path, home: home)
    }

    /// No trailing "/" or ".git".
    private static func trimmed(_ text: String) -> String {
        var result = Substring(text)
        while result.hasSuffix("/") { result = result.dropLast() }
        if result.hasSuffix(".git") { result = result.dropLast(4) }
        return String(result)
    }
}
