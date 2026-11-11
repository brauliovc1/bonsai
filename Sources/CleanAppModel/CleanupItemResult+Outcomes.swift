import CleanCore
import Foundation

extension CleanupItemResult {
    init(_ outcome: RemovalOutcome) {
        self.init(outcome.removed ? .cleaned : (outcome.changedSinceConfirmed ? .refused : .failed), freedBytes: outcome.freedBytes,
                  detail: outcome.error ?? "Removed; the branch or commit is kept in Recently removed.", warnings: outcome.warnings)
    }

    init(_ outcome: LightCleanOutcome) {
        guard let folder = outcome.folders.first else {
            self.init(.refused, detail: outcome.error ?? "Nothing was reached.")
            return
        }
        switch folder.status {
        case .deleted(let bytes): self.init(.cleaned, freedBytes: bytes, warnings: outcome.warnings)
        case .refused(let why): self.init(.refused, detail: why, warnings: outcome.warnings)
        case .failed(let why): self.init(.failed, detail: why, warnings: outcome.warnings)
        }
    }

    init(_ report: CachesCleanReport) {
        guard let outcome = report.outcomes.first else { self.init(.failed, detail: "Nothing was reached."); return }
        switch outcome.status {
        case .cleaned(_, let bytes, let failures):
            self.init(.cleaned, freedBytes: bytes, warnings: report.warnings + failures)
        case .refused(let why): self.init(.refused, detail: why)
        case .failed(let failures): self.init(.failed, detail: failures.joined(separator: "\n"), warnings: report.warnings)
        }
    }

    init(_ report: CleanupCommandReport) {
        let warnings = report.logError.map { [$0] } ?? []
        self.init(report.succeeded ? .cleaned : (report.didRun ? .failed : .refused), freedBytes: report.freedBytes,
                  detail: [report.summary, report.output].filter { !$0.isEmpty }.joined(separator: "\n"), warnings: warnings)
    }
}
