import Foundation

public struct BranchLineageReader: Sendable {
    public let git: GitReadOnly
    public let catalog: RefCatalog
    public init(git: GitReadOnly, catalog: RefCatalog) { self.git = git; self.catalog = catalog }

    public func load(branch: String, base: String, origins: [String: BranchOrigin]? = nil) async throws -> BranchLineage {
        let selected = try await resolvedName(branch)
        let baseRef = try await resolvedName(base)
        let detached = selected.hasPrefix("worktree:") ? catalog.worktrees.first { "worktree:" + $0.path == selected } : nil
        let tipSHA = try await git.resolve(detached?.head ?? selected)
        let baseSHA = try await git.resolve(baseRef)
        let query = BranchGit(git: git)
        let tip = try await query.commit(tipSHA)
        let family: BranchFamily
        if let origins { family = BranchFamily(origins: origins) }
        else { family = try await self.family(base: baseRef) }
        let origin: BranchOrigin
        if let known = family.origins[selected] { origin = known }
        else if detached != nil || (catalog.refs.contains { $0.fullName == selected && $0.kind == .remote }) { origin = try await inferOrigin(of: selected, tip: tipSHA, base: baseRef) }
        else { origin = BranchOrigin(parent: nil, source: .unknown, reason: "No branch creation record is available.") }
        let common = try await query.mergeBase(baseSHA, tipSHA)
        let fork = try await forkPoint(origin: origin, tip: tipSHA, fallback: common)
        var effectiveOrigins = family.origins; effectiveOrigins[selected] = origin
        let effectiveFamily = BranchFamily(origins: effectiveOrigins)
        let worktree = detached ?? catalog.worktrees.first { "refs/heads/" + ($0.branch ?? "") == selected }
        return BranchLineage(branch: selected, base: baseRef, tip: tip, origin: origin,
            forkPoint: fork.0, forkSource: fork.1, merged: await merged(tip: tipSHA, base: baseSHA),
            children: effectiveFamily.children(of: selected), parentChain: effectiveFamily.chain(from: selected, through: baseRef),
            upstream: await upstream(selected), worktree: worktree?.path,
            problems: common == nil ? [BranchMap.unrelated] : [])
    }

    public func family(base: String, includeRemotes: Bool = false) async throws -> BranchFamily {
        let baseRef = try await resolvedName(base)
        let symbolic = try await git.string(["for-each-ref", "--format=%(refname)%00%(symref)", "refs/remotes"])
        let aliases = Set(symbolic.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            return fields.count == 2 && !fields[1].isEmpty ? String(fields[0]) : nil
        })
        let refs = catalog.refs.filter { ($0.kind == .local || (includeRemotes && $0.kind == .remote)) && !aliases.contains($0.fullName) }
        let records = await BoundedConcurrency.map(refs, limit: BranchMap.concurrency) { ref in
            do {
                let data = try await git.data(["log", "-g", "--date=raw", BranchReflog.format, ref.fullName, "--"])
                return (ref.fullName, BranchReflog.creation(in: data))
            } catch { return (ref.fullName, Optional<BranchOrigin>.none) }
        }
        var origins: [String: BranchOrigin] = [:]
        for (ref, record) in records {
            if ref == baseRef { continue }
            if let record, let parent = record.parent {
                origins[ref] = BranchOrigin(parent: canonical(parent), source: .reflog, date: record.date,
                                           atSHA: record.atSHA, reason: record.reason)
            }
        }
        for ref in refs where ref.fullName != baseRef && origins[ref.fullName] == nil {
            try Task.checkCancellation()
            origins[ref.fullName] = try await inferOrigin(of: ref.fullName, tip: ref.sha, base: baseRef)
        }
        return BranchFamily(origins: origins)
    }

    private func resolvedName(_ name: String) async throws -> String {
        if name == "HEAD" { return (try? await git.string(["symbolic-ref", "--quiet", "HEAD"])) ?? name }
        return canonical(name)
    }

    public func timeline(entries: [BranchMapEntry], origins: [String: BranchOrigin]) async throws -> [String: BranchTimelineEntry] {
        let values = await BoundedConcurrency.map(entries, limit: BranchMap.concurrency) { entry in
            do {
                try Task.checkCancellation()
                let origin = origins[entry.ref] ?? BranchOrigin(parent: nil, source: .unknown, reason: "")
                let fork = try await forkPoint(origin: origin, tip: entry.sha, fallback: entry.metrics.fork?.sha).0
                guard let fork else { return BranchTimelineEntry(ref: entry.ref, fork: nil, commits: [], commitCount: 0, problem: entry.metrics.problem) }
                let range = fork.sha + ".." + entry.sha
                let countText = try await git.string(["rev-list", "--count", range])
                guard let count = Int(countText) else { throw CompareError("The commit count could not be read.") }
                let commits = try await BranchGit(git: git).commits(range, maximum: BranchMap.dotLimit, flags: ["--reverse", "--topo-order"])
                return BranchTimelineEntry(ref: entry.ref, fork: fork, commits: commits, commitCount: count, problem: nil)
            } catch { return BranchTimelineEntry(ref: entry.ref, fork: entry.metrics.fork, commits: [], commitCount: 0, problem: String(describing: error)) }
        }
        try Task.checkCancellation()
        return Dictionary(uniqueKeysWithValues: values.map { ($0.ref, $0) })
    }

    func canonical(_ name: String) -> String {
        if let exact = catalog.refs.first(where: { $0.fullName == name }) { return exact.fullName }
        if let local = catalog.refs.first(where: { $0.kind == .local && $0.name == name }) { return local.fullName }
        return catalog.refs.first(where: { $0.name == name })?.fullName ?? name
    }

    private func inferOrigin(of selected: String, tip: String, base: String) async throws -> BranchOrigin {
        let query = BranchGit(git: git)
        var candidates = catalog.refs.filter { $0.kind != .tag && $0.fullName != selected }
        if !candidates.contains(where: { $0.fullName == base }), base != selected, let sha = try? await git.resolve(base) {
            candidates.append(RefCatalog.Ref(name: base, fullName: base, sha: sha, kind: .local))
        }
        let shared = await BoundedConcurrency.map(candidates, limit: BranchMap.concurrency) { candidate -> (RefCatalog.Ref, BranchHistoryCommit)? in
            do {
                guard let sha = try await query.mergeBase(tip, candidate.sha) else { return nil }
                // A descendant branch cannot be evidence that its ancestor was cut from it.
                if sha == tip && candidate.sha != tip && candidate.fullName != base { return nil }
                return (candidate, try await query.commit(sha))
            } catch { return nil }
        }.compactMap { $0 }
        try Task.checkCancellation()
        let best = shared.sorted { left, right in
            if left.1.date != right.1.date { return left.1.date > right.1.date }
            if (left.0.fullName == base) != (right.0.fullName == base) { return left.0.fullName == base }
            if left.0.kind != right.0.kind { return left.0.kind == .local }
            return left.0.fullName < right.0.fullName
        }.first
        guard let best else { return BranchOrigin(parent: nil, source: .unknown, reason: "No branch with shared history was found; local reflog history may have expired.") }
        return BranchOrigin(parent: best.0.fullName, source: .sharedHistory, atSHA: best.1.sha,
            reason: "Probably: its most recent shared commit is with \(best.0.name). The local creation reflog is unavailable or does not name a branch.")
    }

    private func forkPoint(origin: BranchOrigin, tip: String, fallback: String?) async throws -> (BranchHistoryCommit?, BranchLineage.ForkSource) {
        let query = BranchGit(git: git)
        if origin.source == .reflog, let sha = origin.atSHA, let parent = origin.parent,
           !["refs/heads/", "refs/remotes/", "refs/tags/"].contains(where: parent.hasPrefix) {
            return (try await query.commit(sha), .creationRecord)
        }
        if let parent = origin.parent {
            if let sha = try? await query.mergeBase(parent, tip, forkPoint: true) { return (try await query.commit(sha), .parentReflog) }
            if let sha = try? await query.mergeBase(parent, tip) { return (try await query.commit(sha), .mergeBase) }
        }
        if let sha = origin.atSHA, origin.source == .reflog { return (try await query.commit(sha), .creationRecord) }
        if let fallback { return (try await query.commit(fallback), .mergeBase) }
        return (nil, .unavailable)
    }
}
