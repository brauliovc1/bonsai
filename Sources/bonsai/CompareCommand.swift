import ArgumentParser
import CleanCore
import Foundation

struct CompareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "compare", abstract: "Review branch changes since their merge base. Read-only; never fetches.")
    @Option(help: "A Git checkout (defaults to the current folder).") var repo: String?
    @Argument(help: "The base branch, remote branch or tag.") var base: String
    @Argument(help: "The branch, tag or worktree folder to compare.") var compare: String
    @Flag(help: "Print the range, commits, merge check and file list as JSON.") var json = false

    func run() async throws {
        let environment = Launch.environment
        guard let executable = environment.tools.git else { throw ValidationError("Git was not found. Install the Xcode Command Line Tools or Homebrew Git.") }
        let folder = CleanEnvironment.expand(repo ?? FileManager.default.currentDirectoryPath, home: environment.homeDirectory)
        let git = try GitReadOnly(repository: folder, executable: executable, timeout: environment.timeouts.git)
        let candidate = CleanEnvironment.expand(compare, home: environment.homeDirectory)
        var directory: ObjCBool = false
        let isFolder = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory) && directory.boolValue
        let selection: CompareSelection = isFolder ? .worktree(candidate.path) : .ref(compare)
        let result = try await CompareReader(git: git).load(base: base, compare: selection)
        if json {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        } else {
            print(result.summary)
            for file in result.files {
                let counts = file.isBinary ? "binary" : "+\(file.additions) −\(file.deletions)"
                let note = file.notCommitted ? " · Not committed" : ""
                print("\(file.status.rawValue)  \(counts)  \(DiffText.decode(Data(file.path.utf8)))\(note)")
            }
            if let detail = result.merge.detail { print(detail.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
}
