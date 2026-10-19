import HavenCore
import SwiftUI

/// Browse any folder (pinned folders, Desktop, Documents, Downloads…), live from disk.
struct FolderView: View {
    let path: String
    @State private var items: [FileItem] = []
    @State private var loaded = false
    @State private var loadedKey = ""
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }
    private var store: LibraryStore { .shared }

    private var key: String { "\(path)|\(store.version)|\(prefs.sortOrder.rawValue)" }

    var body: some View {
        FileCollectionView(
            items: items,
            listID: loadedKey,
            isLoading: !loaded,
            emptySymbol: "folder",
            emptyTitle: "This folder is empty",
            emptyMessage: "Files you put in \(FileManager.default.displayName(atPath: path)) will appear here."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: FileManager.default.displayName(atPath: path), subtitle: tildePath(path), symbol: "folder")
                breadcrumbs
                HStack {
                    let pinned = prefs.pinnedFolders.contains(path)
                    Button {
                        model.togglePin(path)
                    } label: {
                        Label(pinned ? "Unpin" : "Pin to Sidebar", systemImage: pinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("folder.pin")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task(id: key) {
            let p = path
            let rootID = store.root(for: path)?.id ?? "custom:" + path
            let sort = prefs.sortOrder
            let options = store.scanOptions
            let result = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let listing = FileScanner.list(directory: p, rootID: rootID, options: options)
                let folders = sort.sorted(listing.filter { $0.kind == .folder })
                let files = sort.sorted(listing.filter { $0.kind != .folder })
                return folders + files
            }.value
            if Task.isCancelled { return }
            items = result
            loaded = true
            loadedKey = key
        }
    }

    private var breadcrumbs: some View {
        let comps = crumbs
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(comps.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button(crumb.name) { model.navigate(to: .folder(crumb.path)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == comps.count - 1 ? Color.primary : Color.secondary)
                        .font(.callout)
                        .disabled(index == comps.count - 1)
                }
            }
        }
    }

    private var crumbs: [(name: String, path: String)] {
        let home = NSHomeDirectory()
        var result: [(String, String)] = []
        var current = path
        while true {
            result.insert((FileManager.default.displayName(atPath: current), current), at: 0)
            if current == home || current == "/" || result.count > 8 { break }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return result.map { (name: $0.0, path: $0.1) }
    }
}
