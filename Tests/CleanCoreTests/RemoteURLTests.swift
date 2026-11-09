@testable import CleanCore
import Foundation
import Testing

@Suite("Remote URLs and git info parsing")
struct RemoteURLTests {
    /// Shaped like a GitHub personal access token; it must never survive.
    static let token = "ghp_R2d2C3poX9wingBB8leiaH4nSolo0042"

    @Test func credentialsAreStrippedFromEveryForm() {
        let cases: [(String, String)] = [
            ("https://braulio:\(Self.token)@github.com/brauliovc1/Nexus.git", "https://github.com/brauliovc1/Nexus.git"),
            ("https://\(Self.token)@github.com/brauliovc1/Nexus", "https://github.com/brauliovc1/Nexus"),
            ("https://x-access-token:\(Self.token)@github.com/o/r.git", "https://github.com/o/r.git"),
            ("https://user:p%40ss\(Self.token)@gitlab.example.com:8443/g/sub/r.git?private_token=\(Self.token)#x",
             "https://gitlab.example.com:8443/g/sub/r.git"),
            ("https://me:\(Self.token)@host@evil.example/r.git", "https://evil.example/r.git"),
            ("https://user:pa/\(Self.token)@host.example/r.git", "https://host.example/r.git"),
            ("ssh://git@github.com:22/o/r.git", "ssh://github.com:22/o/r.git"),
            ("ssh://git@[::1]:2222/r.git", "ssh://[::1]:2222/r.git"),
            ("git@github.com:brauliovc1/Nexus.git", "github.com:brauliovc1/Nexus.git"),
            ("deploy:\(Self.token)@host.xz:path/to/r.git", "host.xz:path/to/r.git"),
            ("  https://\(Self.token)@github.com/o/r.git\n", "https://github.com/o/r.git"),
        ]
        for (url, expected) in cases {
            let redacted = RemoteURL.redacted(url)
            #expect(redacted == expected, "\(url)")
            #expect(!redacted.contains(Self.token))
            #expect(!RemoteURL.short(url).contains(Self.token))
        }
    }

    @Test func urlsWithoutCredentialsAreKept() {
        for url in ["https://github.com/o/r.git", "https://host/@scope/pkg.git", "/Users/me/remotes/r.git",
                    "../sibling.git", "file:///Users/me/r.git", "github.com:o/r.git"] {
            #expect(RemoteURL.redacted(url) == url)
        }
    }

    @Test func shortForms() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(RemoteURL.short("https://braulio:\(Self.token)@github.com/brauliovc1/Nexus.git") == "github.com/brauliovc1/Nexus")
        #expect(RemoteURL.short("git@github.com:brauliovc1/Nexus.git") == "github.com/brauliovc1/Nexus")
        #expect(RemoteURL.short("ssh://git@github.com:22/o/r.git/") == "github.com/o/r")
        #expect(RemoteURL.short("ssh://git@[::1]:2222/r.git") == "[::1]/r")
        #expect(RemoteURL.short("https://gitlab.example.com:8443/g/sub/r.git?t=1") == "gitlab.example.com/g/sub/r")
        #expect(RemoteURL.short("/Users/me/remotes/r.git", home: home) == "~/remotes/r.git")
        #expect(RemoteURL.short("file:///Users/me/r.git", home: home) == "~/r.git")
        #expect(RemoteURL.short("/Volumes/X/r.git", home: home) == "/Volumes/X/r.git")
    }

    @Test func tildePaths() {
        let home = URL(fileURLWithPath: "/Users/me/", isDirectory: true)
        #expect(TildePath.abbreviate("/Users/me/Documents/GitHub/Nexus", home: home) == "~/Documents/GitHub/Nexus")
        #expect(TildePath.abbreviate("/Users/me", home: home) == "~")
        #expect(TildePath.abbreviate("/Users/meow/x", home: home) == "/Users/meow/x")
        #expect(TildePath.abbreviate("/tmp/x", home: home) == "/tmp/x")
    }

    @Test func remotesParseFetchAndPush() throws {
        let output = """
            origin\thttps://\(Self.token)@github.com/o/r.git (fetch)
            origin\thttps://\(Self.token)@github.com/o/r.git (push)
            fork\t/Users/me/my remotes/r.git (fetch)
            fork\tgit@github.com:me/r.git (push)
            junk line
            """
        let remotes = GitRemote.parse(output)
        #expect(remotes == [
            GitRemote(name: "origin", url: "https://github.com/o/r.git"),
            GitRemote(name: "fork", url: "/Users/me/my remotes/r.git", pushURL: "github.com:me/r.git"),
        ])
        #expect(remotes[0].pushURL == nil, "same as the fetch URL")
        #expect(GitRemote.preferredOrder([remotes[1], remotes[0]]).map(\.name) == ["origin", "fork"])
        let json = String(decoding: try CleanJSON.encoder().encode(remotes), as: UTF8.self)
        #expect(!json.contains(Self.token))
    }

    @Test func commitRecordsParse() {
        func record(_ sha: String, _ author: String, _ seconds: String, _ subject: String, _ message: String) -> Data {
            Data([sha, author, seconds, subject, message].joined(separator: "\u{1F}").utf8) + Data([0])
        }
        let sha = String(repeating: "a1", count: 20)
        let output = record(sha, "Ana Pérez", "1700000000", "Fix it", "Fix it\n\nBody with a \u{1F} in it.\n")
            + record("not-a-hash", "x", "1", "s", "m")
            + record(String(repeating: "b", count: 40), "x", "soon", "s", "m")
        let commits = CommitSummary.parse(output)
        #expect(commits.count == 1)
        #expect(commits.first?.message == "Fix it\n\nBody with a \u{1F} in it.")
        #expect(commits.first?.author == "Ana Pérez")
        #expect(commits.first?.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commits.first?.shortSHA == "a1a1a1a1")
        #expect(!CommitSummary.isHash("--output=/tmp/x"))
        #expect(!CommitSummary.isHash("ABCDEF12"), "git prints lowercase")
    }

    @Test func upstreamTrackParses() {
        #expect(UpstreamStatus.parse(upstream: "", track: "") == nil)
        #expect(UpstreamStatus.parse(upstream: "origin/a", track: "") == UpstreamStatus(name: "origin/a"))
        #expect(UpstreamStatus.parse(upstream: "origin/a", track: "ahead 2, behind 1")
            == UpstreamStatus(name: "origin/a", ahead: 2, behind: 1))
        #expect(UpstreamStatus.parse(upstream: "origin/a", track: "behind 7")?.behind == 7)
        #expect(UpstreamStatus.parse(upstream: "origin/a", track: "gone")?.isGone == true)
    }
}
