@testable import CleanCore
import Testing

@Suite("Rebuild hints")
struct RebuildHintTests {
    private func lines(_ candidates: [String], root: [String], _ others: [String: [String]] = [:]) -> [String] {
        RebuildHint.lines(candidates: candidates, entries: others.merging(["": root]) { _, root in root })
    }

    @Test func eachFileKindGivesItsLine() {
        #expect(lines(["node_modules"], root: ["package.json", "package-lock.json"]) == ["npm install"])
        #expect(lines(["node_modules"], root: ["pnpm-lock.yaml"]) == ["pnpm install"])
        #expect(lines(["node_modules"], root: ["yarn.lock"]) == ["yarn"])
        #expect(lines([".next"], root: ["next.config.js"]) == [".next comes back with next build or next dev"])
        #expect(lines([".next"], root: ["next.config.mjs"]) == [".next comes back with next build or next dev"])
        #expect(lines([".next"], root: ["next.config.ts"]) == [".next comes back with next build or next dev"])
        #expect(lines([".dart_tool"], root: ["pubspec.yaml"]) == ["flutter pub get"])
        #expect(lines(["Pods"], root: ["Podfile"]) == ["pod install"])
        #expect(lines([".build"], root: ["Package.swift"]) == ["swift build"])
        #expect(lines([".venv"], root: [".venv", "requirements.txt"]) == ["recreate the virtualenv"])
        #expect(lines(["venv"], root: ["venv"]) == ["recreate the virtualenv"])
    }

    @Test func aCheckoutWithNoKnownFileGetsNoLine() {
        #expect(lines(["node_modules", "build", "dist"], root: ["README.md", "Makefile", "node_modules", "build"]).isEmpty)
        #expect(lines([], root: ["package-lock.json", "Podfile"]).isEmpty, "nothing deleted, nothing to get back")
    }

    @Test func aLineNeedsAFolderThatToolBringsBack() {
        // A Swift package next to a deleted node_modules says nothing about it.
        #expect(lines(["node_modules"], root: ["Package.swift", "package-lock.json"]) == ["npm install"])
        #expect(lines(["coverage"], root: ["package-lock.json"]).isEmpty)
    }

    @Test func folderFilesNameTheirFolderAndOnlyCoverFoldersBelowThem() {
        let found = lines(
            ["frontend/node_modules", "frontend/.next", "ios/Pods", "node_modules"],
            root: ["package-lock.json", "node_modules"],
            ["frontend": ["yarn.lock", "next.config.js", ".next", "node_modules"], "ios": ["Podfile", "Pods"]]
        )
        #expect(found == [
            "npm install",
            "yarn (in frontend)",
            ".next comes back with next build or next dev (in frontend)",
            "pod install (in ios)",
        ])
        // frontend's lock file doesn't speak for the root's node_modules.
        #expect(lines(["node_modules"], root: ["node_modules"], ["frontend": ["yarn.lock"]]) == [])
        #expect(RebuildHint.folders(for: ["node_modules", "frontend/node_modules", "frontend/.next", "a/b/Pods"])
            == ["", "frontend", "a/b"])
    }
}
