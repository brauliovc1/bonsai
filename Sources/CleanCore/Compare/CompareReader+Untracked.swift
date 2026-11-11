import Darwin
import Foundation

extension CompareReader {
    struct WorktreeInfo { let bytes: Int; let lines: Int; let binary: Bool; let mode: String }

    /// Read regular files in bounded chunks. A named pipe or device can never block the review screen.
    func worktreeInfo(_ path: String) throws -> WorktreeInfo {
        let file = try worktreeFile(path)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            let data = Data(try FileManager.default.destinationOfSymbolicLink(atPath: file.path).utf8)
            return WorktreeInfo(bytes: data.count, lines: Self.lineCount(data), binary: false, mode: "120000")
        }
        guard values.isRegularFile == true else { throw CompareError("This file type can't be compared: \(path)") }
        let descriptor = open(file.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CompareError("Couldn't open this file: \(path)") }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw CompareError("This file type can't be compared: \(path)")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var count = 0; var lines = 0; var binary = false; var last: UInt8?
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            count += chunk.count; lines += chunk.filter { $0 == 10 }.count
            binary = binary || chunk.contains(0); last = chunk.last
        }
        return WorktreeInfo(bytes: count, lines: lines + (last != nil && last != 10 ? 1 : 0), binary: binary,
            mode: metadata.st_mode & S_IXUSR == 0 ? "100644" : "100755")
    }

    func worktreeFile(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw CompareError("The file path is outside this checkout.")
        }
        let file = git.repository.appending(path: path)
        // A symlink's target is inert text; an intermediate link must stay inside this checkout.
        guard CanonicalPath.isInside(file.deletingLastPathComponent(), directory: git.repository)
                || CanonicalPath.same(file.deletingLastPathComponent(), git.repository) else {
            throw CompareError("The file's folder points outside this checkout.")
        }
        return file
    }

    /// `diff --no-index` is still a read-only diff. It produces valid binary patches and preserves exact
    /// tabs, CRLF and no-newline markers, with no staging, hash-object or temporary user-data writes.
    func untrackedPatch(_ path: String, whitespace: Bool, context: Int) async throws -> Data {
        let file = try worktreeFile(path)
        _ = try worktreeInfo(path)
        var args = ["diff", "--no-index", "--binary", "--full-index", "--no-color", "--unified=\(context)"]
        if whitespace { args.append("--ignore-all-space") }
        args += ["--", "/dev/null", file.path]
        let result = try await git.result(args)
        guard !result.timedOut, result.exitCode == 0 || result.exitCode == 1 else {
            throw CompareError(result.timedOut ? "Git took too long. Refresh to try again." : result.stderr)
        }
        // Only header paths are replaced. Patch payload remains byte-exact, including non-UTF-8 content.
        var output = Data(); var header = true
        for raw in result.stdout.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
            let line = String(decoding: raw, as: UTF8.self)
            let replacement: String?
            if header && line.hasPrefix("diff --git ") { replacement = "diff --git \(quotePath("a/" + path)) \(quotePath("b/" + path))" }
            else if header && line.hasPrefix("--- ") { replacement = "--- /dev/null" }
            else if header && line.hasPrefix("+++ ") { replacement = "+++ \(quotePath("b/" + path))" }
            else { replacement = nil }
            if line.hasPrefix("@@ ") || line == "GIT binary patch" { header = false }
            output.append(replacement.map { Data($0.utf8) } ?? Data(raw)); output.append(10)
        }
        return output
    }

    private func quotePath(_ path: String) -> String {
        guard path.utf8.contains(where: { $0 <= 32 || $0 >= 127 || $0 == 34 || $0 == 92 }) else { return path }
        return "\"" + path.utf8.map { byte -> String in
            if byte == 34 { return "\\\"" }
            if byte == 92 { return "\\\\" }
            if byte < 32 || byte >= 127 { return String(format: "\\%03o", byte) }
            return String(UnicodeScalar(byte))
        }.joined() + "\""
    }
}
