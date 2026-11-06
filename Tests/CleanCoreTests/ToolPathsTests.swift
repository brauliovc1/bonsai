import CleanCore
import Foundation
import Testing

@Suite("ToolPaths")
struct ToolPathsTests {
    private func urls(_ paths: String...) -> [URL] { paths.map { URL(fileURLWithPath: $0) } }

    private func candidates(git: [URL], xcrun: [URL] = [], docker: [URL] = []) -> ToolCandidates {
        ToolCandidates(
            git: git,
            du: urls("/usr/bin/du"),
            lsof: urls("/usr/sbin/lsof"),
            xcrun: xcrun,
            defaults: urls("/usr/bin/defaults"),
            docker: docker,
            requiringDeveloperTools: Set(urls("/usr/bin/git", "/usr/bin/xcrun"))
        )
    }

    @Test func firstExecutableCandidateWins() {
        let executables: Set<String> = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/du",
                                         "/Applications/Docker.app/Contents/Resources/bin/docker"]
        let tools = ToolPaths.resolve(
            candidates: candidates(
                git: urls("/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"),
                docker: urls("/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker")
            ),
            isExecutable: { executables.contains($0.path) },
            developerToolsInstalled: { true }
        )
        #expect(tools.git?.path == "/opt/homebrew/bin/git")
        #expect(tools.du?.path == "/usr/bin/du")
        #expect(tools.docker?.path == "/Applications/Docker.app/Contents/Resources/bin/docker")
        #expect(tools.lsof == nil)
        #expect(tools.defaults == nil)
        #expect(tools.developerToolsInstalled)
    }

    @Test func usrBinGitOnlyWithDeveloperTools() {
        let gitCandidates = urls("/usr/bin/git", "/opt/homebrew/bin/git")
        let withTools = ToolPaths.resolve(
            candidates: candidates(git: gitCandidates, xcrun: urls("/usr/bin/xcrun")),
            isExecutable: { _ in true },
            developerToolsInstalled: { true }
        )
        #expect(withTools.git?.path == "/usr/bin/git")
        #expect(withTools.xcrun?.path == "/usr/bin/xcrun")

        let withoutTools = ToolPaths.resolve(
            candidates: candidates(git: gitCandidates, xcrun: urls("/usr/bin/xcrun")),
            isExecutable: { _ in true },
            developerToolsInstalled: { false }
        )
        #expect(withoutTools.git?.path == "/opt/homebrew/bin/git")
        #expect(withoutTools.xcrun == nil)
        #expect(!withoutTools.developerToolsInstalled)

        let onlyShim = ToolPaths.resolve(
            candidates: candidates(git: urls("/usr/bin/git")),
            isExecutable: { _ in true },
            developerToolsInstalled: { false }
        )
        #expect(onlyShim.git == nil)
    }

    @Test func standardCandidatesMatchThePlan() {
        let standard = ToolCandidates.standard
        #expect(standard.git.map(\.path) == ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
        #expect(standard.du.map(\.path) == ["/usr/bin/du"])
        #expect(standard.lsof.map(\.path) == ["/usr/sbin/lsof"])
        #expect(standard.docker.last?.path == "/Applications/Docker.app/Contents/Resources/bin/docker")
        #expect(standard.requiringDeveloperTools.contains(URL(fileURLWithPath: "/usr/bin/git")))
    }

    @Test func liveResolutionFindsGitAndDu() {
        let tools = ToolPaths.resolve()
        #expect(tools.du != nil)
        #expect(tools.git != nil)
    }

    @Test func gitVersionParsingAndMinimum() {
        #expect(GitVersion(parsing: "git version 2.54.0 (Apple Git-157)") == GitVersion(major: 2, minor: 54, patch: 0))
        #expect(GitVersion(parsing: "git version 2.43.0.windows.1\n")?.isSupported == true)
        #expect(GitVersion(parsing: "git version 2.36.0")?.isSupported == true)
        #expect(GitVersion(parsing: "git version 2.35.9")?.isSupported == false)
        #expect(GitVersion(parsing: "git version 1.9")?.isSupported == false)
        #expect(GitVersion(parsing: "git version 3.0")?.isSupported == true)
        #expect(GitVersion(parsing: "not git") == nil)
    }
}
