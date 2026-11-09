@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §8.4: the app's words for every status and reason. The switches below are exhaustive, so a new
/// `SafetyReason` or `WorktreeStatus` case doesn't compile until it has words here and in the app.
@Suite("Worktree status words")
struct WorktreeStatusTextTests {
    private static let process = ProcessCwdIndex.Entry(pid: 42, command: "node", cwd: "/tmp/w")

    /// One sample of every reason.
    static let samples: [SafetyReason] = [
        .mainCheckout, .missingFolder, .locked(reason: "on a drive"), .inUse([process]), .inUseUnknown,
        .uncommitted(count: 3), .hiddenLocalEdits(["a.txt"]), .operationInProgress(["rebase-merge"]), .submodules,
        .nestedCheckouts(["vendor/x"]), .nestedClones([".build/checkouts/kit"]), .nestedSearchIncomplete("cap hit"),
        .localOnlyCommits(count: 2, onBranch: false), .localOnlyCommits(count: 1, onBranch: true),
        .reflogOnlyCommits(count: 1), .stash(count: 2), .ignoredUserFiles([".env"]), .claudeSession,
        .recentlyActive(days: 4), .idleUnknown, .gitError("fatal: bad object"), .staleRecord(leadsTo: "/x/.git"),
    ]

    /// The §8.4 words, color and whether it is a quiet note, written out per case.
    static func expected(_ reason: SafetyReason) -> (text: String, tone: StatusTone, isNote: Bool) {
        switch reason {
        case .mainCheckout: ("Repo folder", .grey, false)
        case .missingFolder: ("Folder missing", .grey, false)
        case .locked: ("Locked", .grey, false)
        case .inUse: ("Open in node", .blue, false)
        case .inUseUnknown: ("Maybe in use", .blue, false)
        case .uncommitted: ("3 unsaved changes", .orange, false)
        case .hiddenLocalEdits: ("Hidden local edits", .orange, false)
        case .operationInProgress: ("Rebase in progress", .orange, false)
        case .submodules: ("Has submodules", .grey, false)
        case .nestedCheckouts: ("Contains other repos", .orange, false)
        // Decision: clones with no local work are a note in both modes (§4.1), so grey, not orange.
        case .nestedClones: ("Contains other repos", .grey, false)
        case .nestedSearchIncomplete, .gitError, .staleRecord: ("Couldn't check", .grey, false)
        case .localOnlyCommits(_, let onBranch):
            onBranch ? ("1 commit not pushed", .grey, true) : ("2 commits not pushed", .orange, false)
        case .reflogOnlyCommits: ("Unreachable commits", .orange, false)
        case .stash: ("2 stashes kept", .grey, true)
        case .ignoredUserFiles: ("Has ignored files", .orange, false)
        case .claudeSession: ("Claude session", .grey, true)
        case .recentlyActive: ("Active 4 days ago", .grey, false)
        case .idleUnknown: ("Activity unknown", .grey, false)
        }
    }

    /// The case's name, exhaustively: the samples cover every case once (twice for the two kinds of
    /// local-only commits).
    static func caseName(_ reason: SafetyReason) -> String {
        switch reason {
        case .mainCheckout: "mainCheckout"
        case .missingFolder: "missingFolder"
        case .locked: "locked"
        case .inUse: "inUse"
        case .inUseUnknown: "inUseUnknown"
        case .uncommitted: "uncommitted"
        case .hiddenLocalEdits: "hiddenLocalEdits"
        case .operationInProgress: "operationInProgress"
        case .submodules: "submodules"
        case .nestedCheckouts: "nestedCheckouts"
        case .nestedClones: "nestedClones"
        case .nestedSearchIncomplete: "nestedSearchIncomplete"
        case .localOnlyCommits: "localOnlyCommits"
        case .reflogOnlyCommits: "reflogOnlyCommits"
        case .stash: "stash"
        case .ignoredUserFiles: "ignoredUserFiles"
        case .claudeSession: "claudeSession"
        case .recentlyActive: "recentlyActive"
        case .idleUnknown: "idleUnknown"
        case .gitError: "gitError"
        case .staleRecord: "staleRecord"
        }
    }

    @Test func everyReasonHasItsWordsAndColor() {
        #expect(Set(Self.samples.map(Self.caseName)).count == 21, "every SafetyReason case is sampled")
        for reason in Self.samples {
            let words = WorktreeStatusText.words(for: reason)
            let expected = Self.expected(reason)
            #expect(words.text == expected.text, "\(reason)")
            #expect(words.tone == expected.tone, "\(reason)")
            #expect(words.isNote == expected.isNote, "\(reason)")
            #expect(words.text == words.text.prefix(1).uppercased() + words.text.dropFirst() || words.text.first?.isNumber == true,
                    "sentence case: \(words.text)")
            #expect(words.text.uppercased() != words.text, "no all caps: \(words.text)")
            for term in ["SAFE", "AUTO-READY", "BLOCKED", "light clean", "main checkout", "verdict", "kind"] {
                #expect(!words.text.contains(term), "\(words.text)")
            }
        }
    }

    @Test func everySentenceSaysBonsaiInPlainWords() {
        for reason in Self.samples {
            let sentence = WorktreeStatusText.sentence(for: reason)
            #expect(!sentence.contains("clean-claude"), "\(sentence)")
            #expect(!sentence.isEmpty && sentence.hasSuffix(".") || sentence.hasPrefix("git couldn't"), "\(sentence)")
        }
        #expect(WorktreeStatusText.sentence(for: .mainCheckout) == "This is the repo itself. Bonsai only removes "
            + "extra worktrees; use Clean dependencies to free space here.", "PLAN §8.5, exact copy")
        #expect(WorktreeStatusText.sentence(for: .claudeSession) == SafetyReason.claudeSessionWarning)
        // The CLI keeps its words.
        #expect(SafetyReason.mainCheckout.sentence.contains("clean-claude"))
        #expect(WorktreeStatus.safe.label == "SAFE")
    }

    /// The chip of each status (§8.4): green when it can be removed, unless a note needs attention; otherwise the
    /// words of the reason that stops it.
    @Test func everyStatusHasItsChip() {
        func assessment(blockers: [SafetyReason] = [], notes: [SafetyReason] = [], autoOnly: [SafetyReason] = []) -> WorktreeAssessment {
            let worktree = Worktree(path: "/tmp/r-a", repoPath: "/tmp/r", head: "abc", branch: "a", isMain: false, kind: .sibling)
            return WorktreeAssessment(worktree: worktree, idle: .idle(days: 40),
                                      safety: SafetyReport(blockers: blockers, notes: notes, autoBlockers: blockers + autoOnly))
        }
        for status in [WorktreeStatus.autoReady, .safe, .blocked(.uncommitted(count: 3)), .inUse] {
            let sample: WorktreeAssessment
            let expected: StatusWords
            switch status {
            case .autoReady:
                sample = assessment()
                expected = StatusWords("Ready · auto clean", .green, symbol: "checkmark.circle.fill")
            case .safe:
                sample = assessment(notes: [.recentlyActive(days: 4)], autoOnly: [.recentlyActive(days: 4)])
                expected = StatusWords("Ready to remove", .green, symbol: "checkmark.circle")
            case .blocked(let reason):
                sample = assessment(blockers: [reason, .inUse([Self.process])])
                expected = WorktreeStatusText.words(for: reason)
            case .inUse:
                sample = assessment(blockers: [.inUse([Self.process])])
                expected = StatusWords("Open in node", .blue, symbol: "macwindow")
            }
            #expect(sample.status == status)
            #expect(WorktreeStatusText.chip(for: sample) == expected, "\(status)")
        }
        // A removable worktree whose ignored files would go with it needs attention: orange, still removable.
        let ignored = assessment(notes: [.ignoredUserFiles([".env"])], autoOnly: [.ignoredUserFiles([".env"])])
        #expect(ignored.status == .safe)
        #expect(WorktreeStatusText.chip(for: ignored).text == "Has ignored files")
        #expect(WorktreeStatusText.needsAttention(ignored))
        // Grey and blue are not "Needs attention": only orange is.
        for reason in Self.samples {
            let blocked = assessment(blockers: [reason])
            #expect(WorktreeStatusText.needsAttention(blocked) == (WorktreeStatusText.chip(for: blocked).tone == .orange), "\(reason)")
        }
        #expect(!WorktreeStatusText.needsAttention(assessment(blockers: [.missingFolder])))
        #expect(!WorktreeStatusText.needsAttention(assessment(blockers: [.inUse([Self.process])])))
        #expect(!WorktreeStatusText.needsAttention(assessment()))
        // Unpushed commits on a branch are a note on a green chip; stashes and Claude sessions too.
        let unpushed = assessment(notes: [.localOnlyCommits(count: 1, onBranch: true), .stash(count: 2), .claudeSession],
                                  autoOnly: [.localOnlyCommits(count: 1, onBranch: true)])
        #expect(WorktreeStatusText.chip(for: unpushed).tone == .green)
        #expect(WorktreeStatusText.notes(for: unpushed) == ["1 commit not pushed", "2 stashes kept", "Claude session"])
        #expect(WorktreeStatusText.explanation(for: unpushed).contains("the branch is kept"))
        // Package clones never make an auto-ready worktree orange.
        let clones = assessment(notes: [.nestedClones([".build/checkouts/kit"])])
        #expect(clones.status == .autoReady && WorktreeStatusText.chip(for: clones).tone == .green)
    }

    /// The one action per status: remove what can go, otherwise what fixes it.
    @Test func theOneActionFitsTheStatus() {
        let fixes: [(SafetyReason, WorktreeFix)] = [
            (.mainCheckout, .cleanDependencies), (.missingFolder, .prune), (.uncommitted(count: 1), .openInTerminal),
            (.nestedCheckouts(["x"]), .showInFinder), (.gitError("x"), .refresh), (.staleRecord(leadsTo: "/x"), .none),
            (.locked(reason: ""), .openInTerminal), (.inUse([Self.process]), .refresh),
        ]
        for (reason, fix) in fixes {
            #expect(WorktreeStatusText.fix(for: reason) == fix, "\(reason)")
        }
        #expect(WorktreeFix.allCases.filter { $0 != .none }.allSatisfy { !$0.title.isEmpty })
    }

    /// "Needs attention" is exactly the orange chips, on the demo world's real verdicts.
    @Test @MainActor func needsAttentionIsExactlyTheOrangeOnes() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let orange = Set(model.linkedRows.filter { $0.chip.tone == .orange }.map(\.id))
        model.filter = .needsAttention
        #expect(Set(model.rows.map(\.id)) == orange)
        #expect(!orange.isEmpty)
        let words = Dictionary(uniqueKeysWithValues: model.linkedRows.map { ($0.url.lastPathComponent, $0.chip.text) })
        #expect(words["atlas-archive"] == "Ready · auto clean")
        #expect(words["atlas-review"] == "Ready to remove")
        #expect(words["atlas-wip"] == "2 unsaved changes")
        #expect(words["beacon-bisect"] == "1 commit not pushed")
        #expect(words["beacon-env"] == "Has ignored files")
        #expect(words["beacon-gone"] == "Folder missing")
        #expect(words["cobalt-py"] == "Contains other repos")
        #expect(words["cobalt-swift"] == "Ready to remove")
        #expect(model.linkedRows.first { $0.url.lastPathComponent == "beacon-spike" }?.notesText == "1 commit not pushed")
    }
}
