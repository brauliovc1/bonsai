import CleanCore
import Foundation

extension GitFixture {
    /// Xcode's package layout under `<folder>/<base>`: a mirror in `repositories/<name>-1a2b3c4d` and a checkout in
    /// `checkouts/<name>` that borrows its objects from the mirror (`clone --shared`, alternates), detached at a
    /// pushed tag. `broken`: the mirror's objects are then deleted, so every git command that reads the
    /// checkout's objects fails ("fatal: bad object HEAD"), as on Braulio's Mac on 2026-11-09.
    @discardableResult
    public func xcodePackage(
        _ name: String,
        in folder: URL,
        base: String = "build/ios/SourcePackages",
        broken: Bool = false
    ) async throws -> (checkout: URL, mirror: URL) {
        let id = UUID().uuidString.prefix(8)
        let remote = remotes.appending(path: "\(name)-\(id).git")
        try await run(["init", "--quiet", "--bare", remote.path], in: url)
        let seed = url.appending(path: "seed-\(name)-\(id)")
        try await run(["clone", "--quiet", remote.path, seed.path], in: url)
        try write("// \(name)\n", to: "Package.swift", in: seed)
        try await commitAll(in: seed, message: "Release")
        try await run(["tag", "1.0.0"], in: seed)
        try await run(["push", "--quiet", "origin", "main", "--tags"], in: seed)

        let packages = folder.appending(path: base, directoryHint: .isDirectory)
        let mirror = packages.appending(path: "repositories/\(name)-1a2b3c4d", directoryHint: .isDirectory)
        let checkout = packages.appending(path: "checkouts/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mirror.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkout.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await run(["clone", "--quiet", "--mirror", remote.path, mirror.path], in: url)
        try await run(["clone", "--quiet", "--shared", mirror.path, checkout.path], in: url)
        try await run(["checkout", "--quiet", "--detach", "1.0.0"], in: checkout)
        if broken {
            let objects = mirror.appending(path: "objects", directoryHint: .isDirectory)
            guard CanonicalPath.isInside(objects, directory: url) else {
                throw FixtureError(description: "refusing to empty \(objects.path): not inside the fixture")
            }
            try FileManager.default.removeItem(at: objects)
            for sub in ["info", "pack"] {
                try FileManager.default.createDirectory(at: objects.appending(path: sub), withIntermediateDirectories: true)
            }
        }
        return (checkout, mirror)
    }
}
