import Foundation

/// What is at `clean-claude` and `Bonsai`, and what the move does about it (PLAN §10.2, P12c review).
extension SettingsFolderMove {
    struct Paths {
        let library: URL
        var old: URL { library.appending(path: oldName, directoryHint: .isDirectory) }
        var new: URL { library.appending(path: newName, directoryHint: .isDirectory) }

        /// The name of what `lstat` finds at `new` as the folder lists it: the disk may not tell `Bonsai` from
        /// `bonsai`, and only an entry spelled `Bonsai` is Bonsai's.
        var newNameOnDisk: String? {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []
            return names.contains(newName) ? newName : names.first { $0.lowercased() == newName.lowercased() }
        }
    }

    enum Decision: Equatable {
        /// `clean-claude` is a real folder and nothing (or only a leftover link) is at `Bonsai`.
        case move
        /// Nothing to move: `Bonsai` is used.
        case useNew
        /// Two real folders: `Bonsai` is used, neither is touched.
        case bothExist
        /// `clean-claude` is used and not moved, because of the reason.
        case keepOld(String)
    }

    /// What to do, from what is at each path now. When `clean-claude` isn't a folder, a leftover `Bonsai -> Bonsai`
    /// link is removed here: no move can be under way then (a move swaps it away while `clean-claude` is still a
    /// folder). `attempts` bounds the looks again after another launch's swap happened in between.
    static func decide(_ paths: Paths, attempts: Int = 3) -> Decision {
        let atOld = Entry(paths.old)
        if atOld != .folder, Entry(paths.new).isLeftoverLink { unlink(paths.new.path) }
        switch atOld {
        case .folder:
            break
        case .link(let text):
            return linked(paths, text: text)
        case .missing, .other:
            return .useNew
        }
        let atNew = Entry(paths.new)
        if atNew.isFreeForTheMove { return .move }
        guard atNew == .folder, paths.newNameOnDisk == newName else { return .keepOld(inTheWay(atNew, paths)) }
        // Two real folders, unless this look straddled another launch's swap (then clean-claude is a link by
        // now): look at it again, and compare both folders' device and inode, before saying so.
        guard Entry(paths.old) == .folder, let oldID = FileID(paths.old, follow: false),
              let newID = FileID(paths.new, follow: false), oldID != newID
        else {
            return attempts > 1 ? decide(paths, attempts: attempts - 1) : .keepOld("the folders changed while Bonsai looked")
        }
        return .bothExist
    }

    /// `clean-claude` is a link. After a move it leads to `Bonsai`: use that. A link to a folder elsewhere (the
    /// person put the folder there) is used as it is and not moved, so this binary and older ones keep sharing its
    /// files and locks. A link that leads nowhere holds nothing: `Bonsai` is used.
    private static func linked(_ paths: Paths, text: String) -> Decision {
        guard let target = FileID(paths.old, follow: true), target.isFolder else { return .useNew }
        if let new = FileID(paths.new, follow: true), new == target { return .useNew }
        return .keepOld("\(paths.old.path) is a link to \(text)")
    }

    private static func inTheWay(_ entry: Entry, _ paths: Paths) -> String {
        switch entry {
        case .link(let text):
            return "\(paths.new.path) is a link to \(text)"
        case .folder:
            let name = paths.newNameOnDisk ?? newName
            return "a folder named \(name) is at \(paths.library.appending(path: name).path), and this disk doesn't "
                + "tell \(newName) from \(name)"
        case .missing, .other:
            return "something that isn't a folder is at \(paths.new.path)"
        }
    }

    /// A file's device and inode (`lstat`, or `stat` when `follow`), and whether it is a folder.
    struct FileID: Equatable {
        let device: dev_t
        let inode: ino_t
        let isFolder: Bool

        init?(_ url: URL, follow: Bool) {
            var info = stat()
            guard (follow ? stat(url.path, &info) : lstat(url.path, &info)) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
            isFolder = info.st_mode & S_IFMT == S_IFDIR
        }
    }

    /// What `lstat` finds at a path (links are not followed).
    enum Entry: Equatable {
        case missing
        case folder
        /// A symbolic link and its text.
        case link(String)
        /// A file, or something `lstat` couldn't read.
        case other

        init(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                self = errno == ENOENT ? .missing : .other
                return
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                self = .folder
            case S_IFLNK:
                let text = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                self = text.map(Entry.link) ?? .other
            default:
                self = .other
            }
        }

        /// The link `Bonsai -> Bonsai` a move makes right before its swap: nothing else makes a link that
        /// points at itself, so one still there was left by a move that stopped in between.
        var isLeftoverLink: Bool { self == .link(SettingsFolderMove.newName) }

        var isFreeForTheMove: Bool { self == .missing || isLeftoverLink }
    }
}
