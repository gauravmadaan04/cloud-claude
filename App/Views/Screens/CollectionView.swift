import HavenCore
import SwiftUI

/// One collection's files. Files stay where they are; removing one from here never touches the file.
struct CollectionView: View {
    let id: UUID
    @State private var renaming = false
    @State private var newName = ""
    @State private var missing: [String] = []
    @State private var confirmDelete = false
    private var collections: CollectionStore { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        if let c = collections.collection(id) {
            LibraryListView(
                title: c.name,
                subtitle: "Collection · \(HavenFormat.count(c.entries.count, "file")) · the files stay where they are",
                symbol: c.symbol,
                source: .collection(c),
                sourceKey: "col:\(id):\(collections.version)",
                emptySymbol: "square.stack",
                emptyTitle: "This collection is empty",
                emptyMessage: "Drag files onto “\(c.name)” in the sidebar, or right-click files and choose Add to Collection.",
                accessory: AnyView(bar(c))
            )
            .dropDestination(for: URL.self) { urls, _ in
                collections.add(urls.map(\.path), to: id) > 0
            }
            .task(id: collections.version) {
                let paths = c.paths
                missing = await Task.detached(priority: .utility) {
                    paths.filter { !FileManager.default.fileExists(atPath: $0) }
                }.value
            }
            .alert("Rename Collection", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Rename") { collections.rename(id, to: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete “\(c.name)”?", isPresented: $confirmDelete) {
                Button("Delete Collection", role: .destructive) {
                    collections.delete(id)
                    model.navigate(to: .home)
                }
            } message: {
                Text("Only the collection goes. The files stay where they are.")
            }
        } else {
            EmptyStateView(symbol: "square.stack", title: "Collection not found", message: "This collection was deleted.")
        }
    }

    private func bar(_ c: FileCollection) -> some View {
        HStack(spacing: 10) {
            if !missing.isEmpty {
                Label("\(HavenFormat.count(missing.count, "file")) moved or deleted", systemImage: "questionmark.folder")
                    .foregroundStyle(.secondary)
                Button("Find Them") {
                    Task {
                        let found = await collections.findMissing(in: id, missing: missing)
                        model.showToast(found == 0 ? "Couldn't find them: they may be deleted" : "Found \(HavenFormat.count(found, "file")) again",
                                        symbol: "magnifyingglass")
                    }
                }
                Button("Remove Them") { collections.remove(Set(missing), from: id) }
            }
            Spacer()
            Button {
                newName = c.name
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete Collection", systemImage: "trash")
            }
            .accessibilityIdentifier("collection.delete")
        }
        .buttonStyle(.bordered)
        .font(.callout)
    }
}
