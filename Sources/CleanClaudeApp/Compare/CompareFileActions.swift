import CleanAppModel
import CleanCore
import SwiftUI

struct CompareFileActions: View {
    let model: CompareModel
    let file: CompareFile

    var body: some View {
        let root: URL = {
            if case .worktree(let path) = model.compare { return URL(fileURLWithPath: path) }
            return URL(fileURLWithPath: model.repository ?? "/")
        }()
        let url = root.appending(path: file.path)
        let exists = FileManager.default.fileExists(atPath: url.path)
        Button("Open file") { FileActions.open(url) }.disabled(!exists)
        Button("Show in Finder") { FolderActions.reveal([url]) }.disabled(!exists)
        Button("Copy path") { FolderActions.copy([url.path]) }
        Button("Copy patch") {
            Task {
                if model.selectedPath != file.path { await model.selectFile(file.path) }
                if let text = try? await model.copyPatch(wholeCompare: false) { FolderActions.copy([text]) }
            }
        }
    }
}
