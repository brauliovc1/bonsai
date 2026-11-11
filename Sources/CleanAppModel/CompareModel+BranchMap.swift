extension CompareModel {
    /// A direct entry from Overview or the menu opens the visual map, including on the first visit to Compare.
    public func openBranchMap() async {
        branches.layout = .timeline
        await branches.setOpen(true)
        await loadIfNeeded()
    }
}
