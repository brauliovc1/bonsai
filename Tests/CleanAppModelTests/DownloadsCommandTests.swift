import CleanCore
import CleanTestSupport
import Darwin
import Foundation
import Testing

@Suite("Downloads CLI")
struct DownloadsCommandTests {
    @Test func jsonAndDryRunInspectOnlyTheTemporaryHome() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let environment = fixture.environment()
        let home = environment.homeDirectory
        let directory = home.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "old.zip")
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-45 * 86400)], ofItemAtPath: file.path)
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var added = timespec(tv_sec: Int(Date().timeIntervalSince1970) - 45 * 86400, tv_nsec: 0)
        try #require(setattrlist(file.path, &attributes, &added, MemoryLayout<timespec>.size, 0) == 0)
        let variables = ["BONSAI_SETTINGS_DIR": environment.settingsDirectory.path,
                         "CLEAN_CLAUDE_SETTINGS_DIR": environment.settingsDirectory.path,
                         "CLAUDE_CONFIG_DIR": environment.claudeConfigDirectory.path]
        let json = try await CLIBinary.run(["downloads", "--home", home.path, "--json"], environment: variables)
        #expect(json.succeeded, "\(json.stderr)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let listing = try decoder.decode(DownloadsListing.self, from: json.stdout)
        #expect(listing.downloads.eligible.map(\.name) == ["old.zip"])
        #expect(listing.trash.bytes == 0 && listing.trash.count == 0)
        let object = try #require(JSONSerialization.jsonObject(with: json.stdout) as? [String: Any])
        #expect(Set(object.keys) == ["downloads", "trash", "timeMachine"])
        let preview = try await CLIBinary.run(["downloads", "--home", home.path, "--move-to-trash"], environment: variables)
        #expect(preview.succeeded && preview.stdoutString.contains("Would move 1 file"), "\(preview.stderr)")
        #expect(preview.stdoutString.contains("Nothing was changed."))
        #expect(try String(contentsOf: file, encoding: .utf8) == "fixture")
        #expect(try RemovalLog(environment: environment).entries().isEmpty)
        // A different home is an inspection seam, never an alternate cleanup root.
        let refused = try await CLIBinary.run(["downloads", "--home", home.path, "--move-to-trash", "--yes"], environment: variables)
        #expect(!refused.succeeded && refused.stderr.contains("listing and dry runs only"))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func validationRejectsYesWithoutAnActionAndJSONWithAnAction() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let variables = ["BONSAI_SETTINGS_DIR": directory.url.appending(path: "settings").path,
                         "CLEAN_CLAUDE_SETTINGS_DIR": directory.url.appending(path: "settings").path,
                         "CLAUDE_CONFIG_DIR": directory.url.appending(path: "claude").path]
        for arguments in [["downloads", "--yes"], ["downloads", "--move-to-trash", "--json"]] {
            let result = try await CLIBinary.run(arguments, environment: variables)
            #expect(!result.succeeded)
        }
    }
}
