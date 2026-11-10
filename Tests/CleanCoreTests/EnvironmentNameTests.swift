import CleanCore
import Foundation
import Testing

/// PLAN §10.2: `BONSAI_*` first, the old `CLEAN_CLAUDE_*` name second, through one reader.
@Suite("Environment names")
struct EnvironmentNameTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test func theOldNamesAreTheCleanClaudeOnes() {
        #expect(EnvironmentName.settingsDirectory.oldName == "CLEAN_CLAUDE_SETTINGS_DIR")
        #expect(EnvironmentName.scanRoots.oldName == "CLEAN_CLAUDE_SCAN_ROOTS")
    }

    @Test(arguments: EnvironmentName.allCases)
    func newOldBothOrNeither(_ variable: EnvironmentName) {
        #expect(variable.value(in: [variable.name: "/new"]) == "/new", "new only")
        #expect(variable.value(in: [variable.oldName: "/old"]) == "/old", "old only")
        #expect(variable.value(in: [variable.name: "/new", variable.oldName: "/old"]) == "/new", "both: new wins")
        #expect(variable.value(in: [:]) == nil, "neither")
        #expect(variable.value(in: [variable.name: "", variable.oldName: "/old"]) == "/old", "empty counts as unset")
        #expect(variable.value(in: [variable.name: "", variable.oldName: ""]) == nil)
        #expect(variable.isPresent(in: [variable.name: ""]) && variable.isPresent(in: [variable.oldName: ""]))
        #expect(!variable.isPresent(in: [:]) && !variable.isPresent(in: ["CLAUDE_CONFIG_DIR": "/x"]))
    }

    /// The environment reads both variables through it.
    @Test func theEnvironmentReadsBothNames() {
        func environment(_ variables: [String: String]) -> CleanEnvironment {
            CleanEnvironment.make(homeDirectory: home, variables: variables, tools: ToolPaths())
        }
        let new = environment(["BONSAI_SETTINGS_DIR": "/s/new", "BONSAI_SCAN_ROOTS": "/r/new"])
        #expect(new.settingsDirectory.path == "/s/new" && new.scanRootsOverride?.map(\.path) == ["/r/new"])
        let old = environment(["CLEAN_CLAUDE_SETTINGS_DIR": "/s/old", "CLEAN_CLAUDE_SCAN_ROOTS": "/r/old:/r/two"])
        #expect(old.settingsDirectory.path == "/s/old" && old.scanRootsOverride?.map(\.path) == ["/r/old", "/r/two"])
        let both = environment([
            "BONSAI_SETTINGS_DIR": "/s/new", "BONSAI_SCAN_ROOTS": "/r/new",
            "CLEAN_CLAUDE_SETTINGS_DIR": "/s/old", "CLEAN_CLAUDE_SCAN_ROOTS": "/r/old",
        ])
        #expect(both.settingsDirectory.path == "/s/new" && both.scanRootsOverride?.map(\.path) == ["/r/new"])
        let neither = environment([:])
        #expect(neither.settingsDirectory.path == "/Users/tester/Library/Application Support/Bonsai")
        #expect(neither.scanRootsOverride == nil)
    }
}
