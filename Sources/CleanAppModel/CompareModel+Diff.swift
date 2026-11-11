import CleanCore
import Foundation

extension CompareModel {
    public func selectFile(_ path: String) async {
        diffTask?.cancel(); prefetchTask?.cancel()
        fileGeneration += 1
        let token = fileGeneration
        selectedPath = path; document = nil; patchText = ""; contextLines = 3; isLoadingDiff = true
        if let reader, let range = activeRange, let i = files.firstIndex(where: { $0.path == path }) {
            do {
                let detailed = try await reader.fileDetails(files[i], range: range)
                guard token == fileGeneration, let position = files.firstIndex(where: { $0.path == path }) else { return }
                files[position] = detailed
            } catch {
                if token == fileGeneration { problem = "Couldn't read this file. \(error)" }
                if token == fileGeneration { isLoadingDiff = false }
                return
            }
        }
        await loadDiff(path, token: token)
    }

    func loadDiff(_ path: String, token: Int) async {
        guard let file = files.first(where: { $0.path == path }), let reader, let range = activeRange else { return }
        guard !file.isBinary, !diffIsCollapsed else { isLoadingDiff = false; return }
        isLoadingDiff = true
        let whitespace = ignoresWhitespace; let context = contextLines
        let key = "\(range.mergeBase):\(range.compareSHA):\(path):\(whitespace):\(context)"
        let task = Task {
            defer { if token == fileGeneration { isLoadingDiff = false } }
            do {
                let cached: (Data, DiffDocument)
                if let found = cache[key] { cached = found }
                else {
                    let bytes = try await reader.patch(file: file, range: range, whitespace: whitespace, context: context)
                    let parsed = await Task.detached { DiffParser.parse(bytes) }.value
                    cached = (bytes, parsed)
                }
                try Task.checkCancellation()
                guard token == fileGeneration else { return }
                cache[key] = cached; document = cached.1; patchText = DiffText.decode(cached.0)
                prefetch(after: file, reader: reader, range: range, whitespace: whitespace)
            } catch is CancellationError {} catch {
                if token == fileGeneration { problem = "Couldn't read this diff. \(error)" }
            }
        }
        diffTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func prefetch(after file: CompareFile, reader: CompareReader, range: CompareRange, whitespace: Bool) {
        guard let i = visibleFiles.firstIndex(where: { $0.path == file.path }), i + 1 < visibleFiles.count else { return }
        let next = visibleFiles[i + 1]
        guard !next.isBinary, !next.isLarge, !next.isGenerated else { return }
        let token = generation; let fileToken = fileGeneration
        prefetchTask = Task {
            do {
                let bytes = try await reader.patch(file: next, range: range, whitespace: whitespace)
                let parsed = await Task.detached { DiffParser.parse(bytes) }.value
                try Task.checkCancellation()
                if generation == token, fileGeneration == fileToken {
                    cache["\(range.mergeBase):\(range.compareSHA):\(next.path):\(whitespace):3"] = (bytes, parsed)
                }
            } catch {}
        }
    }

    public func showAnyway() async {
        guard let path = selectedPath else { return }
        expandedLargeFiles.insert(path)
        await selectFile(path)
    }

    public func showMoreContext() async {
        guard let path = selectedPath else { return }
        contextLines += 20
        diffTask?.cancel(); prefetchTask?.cancel(); fileGeneration += 1
        await loadDiff(path, token: fileGeneration)
    }

    public func changeWhitespace() async {
        if let path = selectedPath { await selectFile(path) }
    }

    public func selectCommit(_ sha: String?) async {
        guard let reader, let snapshot else { return }
        generation += 1; let token = generation
        diffTask?.cancel(); prefetchTask?.cancel(); fileGeneration += 1
        document = nil; selectedPath = nil; selectedCommit = sha; problem = nil
        do {
            let range: CompareRange
            if let sha, let commit = snapshot.range.commits.first(where: { $0.sha == sha }) {
                range = try await reader.commitRange(commit, original: snapshot.range)
            } else { range = snapshot.range }
            let fresh = sha == nil ? snapshot.files : try await reader.files(from: range.mergeBase, to: range.compareSHA)
            guard token == generation else { return }
            activeRange = range; files = fresh
            if let first = visibleFiles.first { await selectFile(first.path) }
        } catch { if token == generation { problem = "Couldn't read this commit. \(error)" } }
    }

    public func copyPatch(wholeCompare: Bool) async throws -> String {
        guard let reader, let range = wholeCompare ? snapshot?.range : activeRange else { return "" }
        let bytes = try await reader.patch(file: wholeCompare ? nil : selectedFile, range: range, whitespace: ignoresWhitespace)
        return DiffText.decode(bytes)
    }
}
