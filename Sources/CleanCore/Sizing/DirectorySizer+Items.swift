import Foundation

/// `DirectorySizer` measures folders only. These methods also accept single files, which Docker's
/// `Docker.raw`, the Claude Code version binaries and the desktop app's loose files need: `du` reports
/// the blocks a file really occupies, so a sparse 400 GB disk image counts for what it allocates.
extension DirectorySizer {
    /// Allocated bytes of a folder or a single file, or nil when it does not exist.
    public func allocatedSize(ofItem item: URL) async throws -> Int64? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return try await size(of: item)
        }
        let result = try await ProcessRunner.run(executable: du, arguments: ["-skx", item.path], timeout: timeout)
        if result.timedOut {
            throw SizeError(description: "du timed out")
        }
        guard let kilobytes = Self.parseKilobytes(result.stdout) else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SizeError(description: "du failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
        }
        return kilobytes * 1024
    }

    /// Sizes of many files and folders, at most `maxConcurrent` at a time. Missing items are left out;
    /// failures come back as issues.
    public func allocatedSizes(ofItems items: [URL]) async -> (sizes: [String: Int64], issues: [ScanIssue]) {
        let outcomes = await BoundedConcurrency.map(items, limit: maxConcurrent) { item -> Result<Int64?, SizeError> in
            do {
                return .success(try await allocatedSize(ofItem: item))
            } catch let error as SizeError {
                return .failure(error)
            } catch {
                return .failure(SizeError(description: "\(error)"))
            }
        }

        var sizes: [String: Int64] = [:]
        var issues: [ScanIssue] = []
        for (item, outcome) in zip(items, outcomes) {
            switch outcome {
            case .success(let bytes?):
                sizes[item.path] = bytes
            case .success(nil):
                break
            case .failure(let error):
                issues.append(ScanIssue(kind: .sizeFailed, path: item.path, message: error.description))
            }
        }
        return (sizes, issues)
    }
}
