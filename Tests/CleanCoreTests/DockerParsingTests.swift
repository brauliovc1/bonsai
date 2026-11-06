@testable import CleanCore
import Foundation
import Testing

@Suite("Docker output parsing")
struct DockerParsingTests {
    @Test(arguments: [
        ("0B", Int64(0)),
        ("1.2kB", 1_200),
        ("512MB", 512_000_000),
        ("12.3GB", 12_300_000_000),
        ("3.4GB", 3_400_000_000),
        ("1.5TB", 1_500_000_000_000),
        ("512MB (40%)", 512_000_000),
        ("0B (0%)", 0),
        ("  7B  ", 7),
        ("2 GB", 2_000_000_000),
    ])
    func readsDockerSizes(text: String, expected: Int64) {
        #expect(DockerSizeParser.bytes(from: text) == expected)
    }

    @Test(arguments: ["", "GB", "abc", "12.3", "12.3XB", "-5MB", "1.2.3GB", "(40%)", "N/A"])
    func rejectsWhatIsNotASize(text: String) {
        #expect(DockerSizeParser.bytes(from: text) == nil)
    }

    private static let dfOutput = """
        {"Active":"3","Reclaimable":"5.2GB (62%)","Size":"8.4GB","TotalCount":"12","Type":"Images"}
        {"Active":"1","Reclaimable":"0B (0%)","Size":"1.2kB","TotalCount":"1","Type":"Containers"}

        {"Active":"2","Reclaimable":"512MB","Size":"3.4GB","TotalCount":"4","Type":"Local Volumes"}
        this line is not json
        {"Active":"0","Reclaimable":"nonsense","Size":"1GB","TotalCount":"0","Type":"Build Cache"}
        {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
        """

    @Test func parsesDfLinesAndSkipsMalformedOnes() {
        let parsed = DockerUsageRow.parse(Self.dfOutput)
        #expect(parsed.skippedLines == 2)
        #expect(parsed.rows == [
            DockerUsageRow(type: "Images", total: 12, active: 3, sizeBytes: 8_400_000_000, reclaimableBytes: 5_200_000_000),
            DockerUsageRow(type: "Containers", total: 1, active: 1, sizeBytes: 1_200, reclaimableBytes: 0),
            DockerUsageRow(type: "Local Volumes", total: 4, active: 2, sizeBytes: 3_400_000_000, reclaimableBytes: 512_000_000),
            DockerUsageRow(type: "Build Cache", total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
        ])
    }

    @Test func aLineWithoutATypeOrWithOddCountsIsHandledPerField() {
        let output = """
            {"Reclaimable":"1GB","Size":"2GB","TotalCount":"1","Active":"1"}
            {"Active":"x","Reclaimable":"1GB (50%)","Size":"2GB","TotalCount":"","Type":"Images"}
            {"Active":2,"Reclaimable":"0B","Size":"1MB","TotalCount":3,"Type":"Containers"}
            """
        let parsed = DockerUsageRow.parse(output)
        #expect(parsed.skippedLines == 1)
        #expect(parsed.rows.map(\.type) == ["Images", "Containers"])
        #expect(parsed.rows[0].total == 0 && parsed.rows[0].active == 0)
        #expect(parsed.rows[1].total == 3 && parsed.rows[1].active == 2)
    }

    @Test func emptyOutputHasNoRows() {
        let parsed = DockerUsageRow.parse("")
        #expect(parsed.rows.isEmpty && parsed.skippedLines == 0)
    }

    @Test func reclaimableTotalsLeaveVolumesOutOfThePruneCeiling() {
        let report = DockerReport(state: .running, usage: DockerUsageRow.parse(Self.dfOutput).rows)
        #expect(report.reclaimableBytes == 5_712_000_000)
        #expect(report.pruneCeilingBytes == 5_200_000_000)
    }

    @Test func readsTheReclaimedSpaceLineOfAPrune() {
        let output = "Deleted Containers:\nabc123\n\nDeleted build cache objects:\nxyz\n\nTotal reclaimed space: 1.2GB"
        #expect(DockerCleaner.reclaimedSpace(in: output) == 1_200_000_000)
        #expect(DockerCleaner.reclaimedSpace(in: "Total reclaimed space: 0B") == 0)
        #expect(DockerCleaner.reclaimedSpace(in: "nothing here") == nil)
        #expect(DockerCleaner.reclaimedSpace(in: "Total reclaimed space: soon") == nil)
    }
}
