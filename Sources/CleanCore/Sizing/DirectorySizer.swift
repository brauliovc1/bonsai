import Foundation

/// Measures folders with `du -skx` (hard links counted once, one volume). Sizes are estimates: APFS clones
/// share blocks, so the space actually freed by a removal can be lower.
public struct DirectorySizer: Sendable {
    public var du: URL
    public var maxConcurrent: Int
    public var timeout: Duration

    public init(du: URL, maxConcurrent: Int = 4, timeout: Duration = .seconds(300)) {
        self.du = du
        self.maxConcurrent = maxConcurrent
        self.timeout = timeout
    }

    public struct SizeError: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    /// Bytes used by `directory`, or nil when it does not exist. A non-zero exit from `du` (unreadable
    /// subfolders) is accepted as long as stdout still starts with a number.
    public func size(of directory: URL) async throws -> Int64? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        let result = try await ProcessRunner.run(
            executable: du,
            arguments: ["-skx", directory.path],
            timeout: timeout
        )
        if result.timedOut {
            throw SizeError(description: "du timed out")
        }
        guard let kilobytes = Self.parseKilobytes(result.stdout) else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SizeError(description: "du failed (exit \(result.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
        }
        return kilobytes * 1024
    }

    /// Sizes of many folders, at most `maxConcurrent` at a time. Missing folders are left out; failures
    /// come back as issues.
    public func sizes(
        of directories: [URL],
        onFinished: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> (sizes: [String: Int64], issues: [ScanIssue]) {
        let total = directories.count
        let outcomes = await BoundedConcurrency.map(
            directories,
            limit: maxConcurrent,
            onCompletion: { onFinished($0, total) }
        ) { directory -> Result<Int64?, SizeError> in
            do {
                return .success(try await size(of: directory))
            } catch let error as SizeError {
                return .failure(error)
            } catch {
                return .failure(SizeError(description: "\(error)"))
            }
        }

        var sizes: [String: Int64] = [:]
        var issues: [ScanIssue] = []
        for (directory, outcome) in zip(directories, outcomes) {
            switch outcome {
            case .success(let bytes?):
                sizes[directory.path] = bytes
            case .success(nil):
                break
            case .failure(let error):
                issues.append(ScanIssue(kind: .sizeFailed, path: directory.path, message: error.description))
            }
        }
        return (sizes, issues)
    }

    /// The leading number of `du -sk` output (`"1234\t/path\n"`), in KiB.
    public static func parseKilobytes(_ stdout: Data) -> Int64? {
        let digits = stdout.prefix { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
        guard !digits.isEmpty else { return nil }
        return Int64(String(decoding: digits, as: UTF8.self))
    }
}
