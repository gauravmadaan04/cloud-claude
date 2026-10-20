import HavenCore
import SwiftUI

struct SidebarView: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme
    @State private var renaming: SavedSearch?
    @State private var newName = ""
    @State private var renamingCollection: UUID?
    @State private var collectionName = ""
    @State private var dropTarget: UUID?
    private var prefs: Prefs { .shared }
    private var store: LibraryStore { .shared }
    private var collections: CollectionStore { .shared }

    var body: some View {
        List(selection: $model.selection) {
            Section {
                row(.home)
                row(.recents)
            }
            Section("Library") {
                ForEach(LibraryCategory.allCases) { c in
                    row(.category(c), tint: theme.isPlayful ? theme.tint(c) : nil, count: store.derived.stats[c]?.count)
                }
            }
            Section("Smart Folders") {
                row(.largeFiles, count: store.derived.largeFiles.count)
                row(.screenshots, count: store.derived.screenshots.count)
                ForEach(prefs.savedSearches) { saved in
                    row(.saved(saved.id), title: saved.name, symbol: saved.symbol)
                        .contextMenu {
                            Button("Rename…") {
                                newName = saved.name
                                renaming = saved
                            }
                            Button("Edit Search") { model.searchText = saved.text }
                            Divider()
                            Button("Delete", role: .destructive) { model.deleteSavedSearch(saved.id) }
                        }
                }
            }
            Section {
                ForEach(collections.collections) { c in
                    row(.collection(c.id), title: c.name, symbol: c.symbol, count: c.entries.count)
                        .background(dropTarget == c.id ? theme.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .dropDestination(for: URL.self) { urls, _ in
                            let added = collections.add(urls.map(\.path), to: c.id)
                            if added > 0 { model.showToast("Added \(HavenFormat.count(added, "file")) to “\(c.name)”", symbol: "square.stack") }
                            return added > 0
                        } isTargeted: { inside in
                            dropTarget = inside ? c.id : (dropTarget == c.id ? nil : dropTarget)
                        }
                        .contextMenu {
                            Button("Rename…") {
                                collectionName = c.name
                                renamingCollection = c.id
                            }
                            Divider()
                            Button("Delete Collection", role: .destructive) {
                                collections.delete(c.id)
                                if model.selection == .collection(c.id) { model.selection = .home }
                            }
                        }
                }
                if collections.collections.isEmpty {
                    Label("Drop files here", systemImage: "tray.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                        .dropDestination(for: URL.self) { urls, _ in
                            model.newCollection(with: urls.compactMap { FileScanner.item(at: $0, rootID: "collection") })
                            return true
                        }
                        .help("Drop files here to start a collection")
                        .accessibilityIdentifier("sidebar.collectionDrop")
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button { model.newCollection(with: []) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New Collection")
                        .accessibilityIdentifier("sidebar.newCollection")
                }
            }
            Section("Tools") {
                row(.sources)
                row(.duplicates)
                row(.cleanup)
                row(.space)
                row(.activity)
            }
            Section("Locations") {
                ForEach(locations, id: \.self) { path in
                    let pinned = prefs.pinnedFolders.contains(path)
                    row(.folder(path), title: FileManager.default.displayName(atPath: path), symbol: locationSymbol(path))
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            if pinned { Button("Unpin") { model.togglePin(path) } }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
        .alert("Rename Saved Search", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let r = renaming, let i = prefs.savedSearches.firstIndex(where: { $0.id == r.id }), !newName.isEmpty {
                    prefs.savedSearches[i].name = newName
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Rename Collection", isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } })) {
            TextField("Name", text: $collectionName)
            Button("Rename") {
                if let id = renamingCollection { collections.rename(id, to: collectionName) }
                renamingCollection = nil
            }
            Button("Cancel", role: .cancel) { renamingCollection = nil }
        }
        .accessibilityIdentifier("sidebar")
    }

    private var locations: [String] {
        let standard = prefs.roots.filter { $0.isProtected && $0.enabled }.map(\.path)
        var seen = Set<String>()
        return (standard + prefs.pinnedFolders).filter { seen.insert($0).inserted }
    }

    private func locationSymbol(_ path: String) -> String {
        if let root = prefs.roots.first(where: { $0.path == path }) { return root.symbol }
        return "folder"
    }

    private func row(_ item: SidebarItem, title: String? = nil, symbol: String? = nil, tint: Color? = nil, count: Int? = nil) -> some View {
        Label {
            Text(title ?? item.title)
        } icon: {
            Image(systemName: theme.symbol(symbol ?? item.symbol))
                .foregroundStyle(tint ?? (theme.isPlayful ? theme.accent : Color.primary.opacity(0.75)))
        }
        .badge(count ?? 0)
        .tag(item)
        .accessibilityIdentifier("sidebar.\(item.accessibilityID)")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.isScanning {
                ProgressView().controlSize(.mini)
                Text(store.hasLoaded ? "Updating…" : "Indexing \(HavenFormat.count(store.scanCount, "file"))…")
            } else if store.text.isWorking {
                ProgressView().controlSize(.mini)
                Text("Reading text \(store.text.processed)/\(store.text.total)")
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text("\(HavenFormat.count(store.derived.fileCount, "file")) indexed")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("sidebar.status")
    }
}
