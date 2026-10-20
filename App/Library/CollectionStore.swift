import Foundation
import HavenCore

/// Your collections, saved in Haven's support folder. Files never move; collections only remember them.
@MainActor
@Observable
final class CollectionStore {
    static let shared = CollectionStore()

    private(set) var collections: [FileCollection] = []
    /// Bumped on every change, so pages showing a collection reload.
    private(set) var version = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private var url: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("collections.json") }

    private init() {
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([FileCollection].self, from: d) {
            collections = c
        }
    }

    func collection(_ id: UUID) -> FileCollection? { collections.first { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout FileCollection) -> Void) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        change(&collections[i])
        changed()
    }

    private func changed() {
        version += 1
        save()
    }

    /// A new collection (named "Collection", "Collection 2"… unless a name is given). Returns its id.
    @discardableResult
    func create(name: String?, paths: [String] = []) -> UUID {
        let base = name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? name! : "Collection"
        var c = FileCollection(name: FileCollection.freeName(base, among: collections.map(\.name)))
        c.add(paths)
        collections.append(c)
        changed()
        addBookmarks(paths, to: c.id)
        return c.id
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    func delete(_ id: UUID) {
        collections.removeAll { $0.id == id }
        changed()
    }

    @discardableResult
    func add(_ paths: [String], to id: UUID) -> Int {
        var added = 0
        update(id) { added = $0.add(paths) }
        if added > 0 { addBookmarks(paths, to: id) }
        return added
    }

    func remove(_ paths: Set<String>, from id: UUID) {
        update(id) { $0.remove(paths) }
    }

    /// Entries follow files Haven renamed or moved.
    func follow(_ moves: [String: String]) {
        var any = false
        for i in collections.indices where collections[i].follow(moves) { any = true }
        if any { changed() }
    }

    /// Bookmarks let a collection find a file again after it was moved outside Haven. Made in the background.
    private func addBookmarks(_ paths: [String], to id: UUID) {
        let list = paths
        Task {
            let marks = await Task.detached(priority: .utility) { () -> [String: Data] in
                var out: [String: Data] = [:]
                for p in list {
                    if let d = try? URL(fileURLWithPath: p).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        out[p] = d
                    }
                }
                return out
            }.value
            guard !marks.isEmpty, let i = self.collections.firstIndex(where: { $0.id == id }) else { return }
            for j in self.collections[i].entries.indices {
                if let d = marks[self.collections[i].entries[j].path] { self.collections[i].entries[j].bookmark = d }
            }
            self.save()
        }
    }

    /// Looks for files that are no longer where the collection remembers them, using their bookmarks.
    /// Returns how many were found again.
    @discardableResult
    func findMissing(in id: UUID, missing: [String]) async -> Int {
        guard let c = collection(id), !missing.isEmpty else { return 0 }
        let wanted = Set(missing)
        let entries = c.entries.filter { wanted.contains($0.path) }
        let found = await Task.detached(priority: .utility) { () -> [String: String] in
            var moves: [String: String] = [:]
            for e in entries {
                guard !FileManager.default.fileExists(atPath: e.path), let mark = e.bookmark else { continue }
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: mark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
                var now = url.path
                // Keep the spelling the collection used (/var rather than /private/var).
                if !e.path.hasPrefix("/private/"), now.hasPrefix("/private/"),
                   FileManager.default.fileExists(atPath: String(now.dropFirst("/private".count))) {
                    now = String(now.dropFirst("/private".count))
                }
                if now != e.path, FileManager.default.fileExists(atPath: now) { moves[e.path] = now }
            }
            return moves
        }.value
        if !found.isEmpty { update(id) { $0.follow(found) } }
        return found.count
    }

    private func save() {
        saveTask?.cancel()
        let snapshot = collections
        let url = self.url
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
    }
}
