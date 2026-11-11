import Foundation

/// A fresh reader owns one consistent metadata view. Refresh creates another reader.
public struct CompareReader: Sendable {
    public let git: GitReadOnly
    public init(git: GitReadOnly) { self.git = git }

    public func load(base: String, compare: CompareSelection) async throws -> CompareSnapshot {
        let baseSHA = try await git.resolve(base)
        let work = try worktreeReader(compare)
        let tip = try await work.git.resolve(compare.refName)
        let mergeBase = try await git.string(["merge-base", baseSHA, tip])
        let counts = try await git.string(["rev-list", "--left-right", "--count", baseSHA + "..." + tip])
            .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        let commits = try await commitList(range: baseSHA + ".." + tip)
        let range = CompareRange(base: base, compare: compare, baseSHA: baseSHA, compareSHA: tip,
            mergeBase: mergeBase, ahead: counts.count == 2 ? counts[1] : 0,
            behind: counts.first ?? 0, commits: commits)
        var files = try await work.files(from: mergeBase, to: compare.isWorktree ? nil : tip)
        if compare.isWorktree {
            let changed = Set(try await work.git.data(["diff", "--name-only", "-z", "--ignore-submodules=all", tip, "--"])
                .split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
            for i in files.indices { files[i].notCommitted = changed.contains(files[i].path) }
            let untracked = try await work.git.data(["ls-files", "--others", "--exclude-standard", "-z"])
            for field in untracked.split(separator: 0) {
                let path = String(decoding: field, as: UTF8.self)
                let info = try work.worktreeInfo(path)
                let binary = info.binary
                files.append(CompareFile(path: path, status: .added,
                    additions: binary ? 0 : info.lines, deletions: 0, isBinary: binary,
                    oldMode: "000000", newMode: info.mode, notCommitted: true, oldBytes: 0, newBytes: info.bytes))
            }
        }
        let merge = await MergeCheck.check(base: baseSHA, compare: tip, using: git)
        return CompareSnapshot(range: range, files: files.sorted { $0.path < $1.path }, merge: merge)
    }

    public func files(from: String, to: String?) async throws -> [CompareFile] {
        let args = ["diff", "--raw", "--numstat", "-z", "-M", "-C", "--find-copies-harder", "--ignore-submodules=all", from]
            + (to.map { [$0] } ?? []) + ["--"]
        return CompareFileParser.parse(try await git.data(args))
    }

    public func patch(file: CompareFile?, range: CompareRange, whitespace: Bool = false, context: Int = 3) async throws -> Data {
        let work = try worktreeReader(range.compare)
        if let file, range.compare.isWorktree, file.status == .added, file.notCommitted {
            let tracked = try await work.git.data(["ls-files", "--cached", "-z", "--", file.path])
            if tracked.isEmpty {
                return try await work.untrackedPatch(file.path, whitespace: whitespace, context: context)
            }
        }
        var arguments = ["diff", "--no-color", "--full-index", "--binary", "-M", "-C", "--find-copies-harder",
            "--ignore-submodules=all", "--unified=\(context)"]
        if whitespace { arguments.append("--ignore-all-space") }
        arguments += [range.mergeBase] + (range.compare.isWorktree ? [] : [range.compareSHA]) + ["--"]
        if let file { arguments += Array(Set([file.oldPath, file.path].compactMap { $0 })).sorted() }
        var bytes = try await work.git.data(arguments)
        if file == nil, range.compare.isWorktree {
            let snapshot = try await load(base: range.base, compare: range.compare)
            for added in snapshot.files where added.status == .added && added.notCommitted {
                let tracked = try await work.git.data(["ls-files", "--cached", "-z", "--", added.path])
                if tracked.isEmpty { bytes.append(try await patch(file: added, range: range, whitespace: whitespace, context: context)) }
            }
        }
        return bytes
    }

    public func fileDetails(_ file: CompareFile, range: CompareRange) async throws -> CompareFile {
        var file = file
        let work = try worktreeReader(range.compare)
        if file.status != .added {
            file.oldBytes = Int(try await git.string(["cat-file", "-s", range.mergeBase + ":" + (file.oldPath ?? file.path)]))
        } else { file.oldBytes = 0 }
        if file.status == .deleted { file.newBytes = 0 }
        else if range.compare.isWorktree {
            let attributes = try FileManager.default.attributesOfItem(atPath: work.git.repository.appending(path: file.path).path)
            file.newBytes = (attributes[.size] as? NSNumber)?.intValue
        } else { file.newBytes = Int(try await git.string(["cat-file", "-s", range.compareSHA + ":" + file.path])) }
        return file
    }

    public func commitList(range: String) async throws -> [CompareCommit] {
        let output = try await git.data(["log", "--reverse", "--topo-order", "--format=%H%x00%s%x00%an%x00%ct%x00", range, "--"])
        let fields = output.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        return stride(from: 0, to: max(0, fields.count - 3), by: 4).compactMap { i in
            let sha = fields[i].trimmingCharacters(in: .newlines)
            guard !sha.isEmpty, let seconds = Double(fields[i + 3]) else { return nil }
            return CompareCommit(sha: sha, subject: fields[i + 1], author: fields[i + 2], date: Date(timeIntervalSince1970: seconds))
        }
    }

    public func commitRange(_ commit: CompareCommit, original: CompareRange) async throws -> CompareRange {
        let parent = try await git.resolve(commit.sha + "^")
        return CompareRange(base: String(commit.sha.prefix(8)) + "^", compare: .ref(commit.sha), baseSHA: parent,
            compareSHA: commit.sha, mergeBase: parent, ahead: 1, behind: 0, commits: [commit])
    }

    private func worktreeReader(_ selection: CompareSelection) throws -> CompareReader {
        guard case .worktree(let path) = selection else { return self }
        return CompareReader(git: try GitReadOnly(repository: URL(fileURLWithPath: path), executable: git.executable, timeout: git.timeout))
    }


    static func lineCount(_ bytes: Data) -> Int { bytes.isEmpty ? 0 : bytes.filter { $0 == 10 }.count + (bytes.last == 10 ? 0 : 1) }
}

extension CompareSelection {
    var refName: String { switch self { case .ref(let name): name; case .worktree: "HEAD" } }
    public var isWorktree: Bool { if case .worktree = self { true } else { false } }
}
