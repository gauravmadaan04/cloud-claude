import AppKit
import Foundation
import HavenCore

struct CategoryStat: Hashable {
    var count = 0
    var bytes: Int64 = 0
}

struct SourceSummary: Identifiable, Hashable {
    let source: DownloadSource
    let count: Int
    let bytes: Int64
    let latest: Date
    let preview: [FileItem]
    var id: String { source.id }
}

/// What a file list on screen shows.
enum CollectionSource: Hashable {
    case recents
    case category(LibraryCategory)
    case largeFiles
    case screenshots
    case source(String)
    case query(SearchQuery)
    case latestDownloads
}

/// Numbers and lists computed from the index in the background after every change.
struct LibraryDerived {
    var stats: [LibraryCategory: CategoryStat] = [:]
    var totalBytes: Int64 = 0
    var fileCount = 0
    var byCategory: [LibraryCategory: [FileItem]] = [:]
    var cleanupCards: [CleanupCard] = []
    var sources: [SourceSummary] = []
    var latestDownloads: [FileItem] = []
    var recents: [FileItem] = []
    var screenshots: [FileItem] = []
    var largeFiles: [FileItem] = []

    static func compute(_ items: [FileItem], cleanup: CleanupSettings, now: Date = Date()) -> LibraryDerived {
        var d = LibraryDerived()
        var byCat: [LibraryCategory: [FileItem]] = [:]
        var bySource: [String: (DownloadSource, [FileItem])] = [:]
        for item in items {
            if item.kind != .folder { d.fileCount += 1; d.totalBytes += item.size }
            if let c = item.category {
                byCat[c, default: []].append(item)
                d.stats[c, default: CategoryStat()].count += 1
                d.stats[c, default: CategoryStat()].bytes += item.size
            }
            if let s = item.source, item.kind != .folder {
                bySource[s.id, default: (s, [])].1.append(item)
            }
        }
        d.byCategory = byCat
        d.sources = bySource.values.map { (source, files) in
            let sorted = files.sorted { $0.arrivalDate > $1.arrivalDate }
            return SourceSummary(source: source, count: files.count, bytes: files.totalSize,
                                 latest: sorted.first?.arrivalDate ?? .distantPast, preview: Array(sorted.prefix(3)))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.latest > $1.latest }
        d.latestDownloads = Array(items.filter { $0.rootID == "downloads" && $0.parentPath.hasSuffix("/Downloads") }
            .sorted { $0.arrivalDate > $1.arrivalDate }.prefix(30))
        let files = items.filter { $0.kind != .folder && $0.kind != .app }
        d.recents = Array(files.prefix(600))
        d.screenshots = items.filter { $0.isScreenshot }.sorted { $0.created > $1.created }
        d.largeFiles = files.filter { $0.size >= 100 * ByteSize.mb }.sorted { $0.size > $1.size }
        d.cleanupCards = CleanupEngine.cards(in: items, settings: cleanup, now: now)
        return d
    }
}

/// Haven's index of your files: loads instantly from disk, rescans in the background and follows changes live.
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    /// Everything indexed, newest activity first.
    private(set) var items: [FileItem] = []
    private(set) var version = 0
    private(set) var isScanning = false
    private(set) var scanCount = 0
    private(set) var hasLoaded = false
    private(set) var lastScan: Date?
    private(set) var derived = LibraryDerived()

    let text = TextIndex()
    let duplicates = DuplicateService()

    @ObservationIgnored private var byPath: [String: FileItem] = [:]
    @ObservationIgnored private var watcher: FSWatcher?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var deriveTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    @ObservationIgnored private var pendingChanges = Set<String>()
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var appSizes: [String: Int64] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var duplicatesRunThisLaunch = false

    private init() {}

    var scanOptions: ScanOptions {
        var o = ScanOptions()
        o.honorTestDates = LaunchOptions.current.isFixtureMode
        return o
    }

    private var supportDir: URL { LaunchOptions.current.supportDirectory }
    private var snapshotURL: URL { supportDir.appendingPathComponent("index.json") }
    private var appSizesURL: URL { supportDir.appendingPathComponent("app-sizes.json") }

    // MARK: Start-up

    func start() {
        guard !started else { return }
        started = true
        let snapURL = snapshotURL
        let sizesURL = appSizesURL
        let enabledIDs = Set(Prefs.shared.enabledRoots.map(\.id))
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> ([FileItem], [String: Int64]) in
                var items: [FileItem] = []
                if let d = try? Data(contentsOf: snapURL), let snap = try? JSONDecoder().decode(IndexSnapshot.self, from: d),
                   snap.version == IndexSnapshot.currentVersion {
                    items = snap.items.filter { enabledIDs.contains($0.rootID) }
                }
                var sizes: [String: Int64] = [:]
                if let d = try? Data(contentsOf: sizesURL), let s = try? JSONDecoder().decode([String: Int64].self, from: d) {
                    sizes = s
                }
                return (items, sizes)
            }.value
            self.appSizes = loaded.1
            if !loaded.0.isEmpty { self.apply(loaded.0, fromSnapshot: true) }
            self.text.load()
            self.duplicates.loadCache()
            self.rescan()
            self.startWatching()
        }
    }

    // MARK: Scanning

    func rescan() {
        scanTask?.cancel()
        let roots = Prefs.shared.enabledRoots
        let options = scanOptions
        isScanning = true
        scanCount = 0
        let store = self
        scanTask = Task.detached(priority: .utility) {
            var all: [FileItem] = []
            var seen = Set<String>()
            for root in roots {
                if Task.isCancelled { return }
                let base = all.count
                let found = FileScanner.scan(root: root, options: options, progress: { n in
                    Task { @MainActor in store.scanCount = base + n }
                }, cancelled: { Task.isCancelled })
                for item in found where seen.insert(item.path).inserted {
                    all.append(item)
                }
            }
            if Task.isCancelled { return }
            let sorted = all.sorted { $0.activityDate > $1.activityDate }
            await MainActor.run {
                let withSizes = sorted.map { item -> FileItem in
                    if item.kind == .app, let s = store.appSizes[LibraryStore.sizeKey(item)] { return item.withSize(s) }
                    return item
                }
                store.apply(withSizes, fromSnapshot: false)
                store.isScanning = false
                store.lastScan = Date()
                store.scheduleSave()
                store.measureAppSizes()
                RulesRunner.shared.runIfDue()
            }
        }
    }

    private func apply(_ newItems: [FileItem], fromSnapshot: Bool) {
        items = newItems
        byPath = Dictionary(newItems.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        version += 1
        hasLoaded = true
        rederive()
        if !fromSnapshot {
            text.enqueue(newItems, scope: Prefs.shared.ocrScope)
            if !duplicatesRunThisLaunch && !LaunchOptions.current.isRunningUnitTests {
                duplicatesRunThisLaunch = true
                duplicates.scan(items: newItems, similar: Prefs.shared.findSimilarPhotos, quietly: true)
            }
        }
    }

    func rederive() {
        deriveTask?.cancel()
        let snapshot = items
        let cleanup = Prefs.shared.cleanup
        let store = self
        deriveTask = Task.detached(priority: .userInitiated) {
            let d = LibraryDerived.compute(snapshot, cleanup: cleanup)
            if Task.isCancelled { return }
            await MainActor.run { store.derived = d }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = IndexSnapshot(rootPaths: Prefs.shared.enabledRoots.map(\.path), items: items)
        let url = snapshotURL
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: App sizes

    nonisolated static func sizeKey(_ item: FileItem) -> String {
        "\(item.path)|\(Int(item.modified.timeIntervalSince1970))"
    }

    private func measureAppSizes() {
        sizeTask?.cancel()
        let apps = items.filter { $0.kind == .app && $0.size == 0 }
        guard !apps.isEmpty else { return }
        let url = appSizesURL
        let store = self
        sizeTask = Task.detached(priority: .background) {
            var measured: [String: Int64] = [:]
            for app in apps {
                if Task.isCancelled { break }
                measured[LibraryStore.sizeKey(app)] = FileScanner.bundleSize(app.path, cancelled: { Task.isCancelled })
            }
            let results = measured
            await MainActor.run {
                store.applyAppSizes(results, saveTo: url)
            }
        }
    }

    private func applyAppSizes(_ results: [String: Int64], saveTo url: URL) {
        appSizes.merge(results) { _, new in new }
        var changed = false
        items = items.map { item in
            if item.kind == .app, item.size == 0, let s = results[LibraryStore.sizeKey(item)] {
                changed = true
                let updated = item.withSize(s)
                byPath[item.path] = updated
                return updated
            }
            return item
        }
        if changed {
            version += 1
            rederive()
            scheduleSave()
        }
        if let data = try? JSONEncoder().encode(appSizes) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Live updates

    private func startWatching() {
        let paths = Prefs.shared.enabledRoots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        let store = self
        watcher = FSWatcher(paths: paths) { changed, mustRescan in
            Task { @MainActor in
                if mustRescan { store.rescan() } else { store.noteChanges(changed) }
            }
        }
        watcher?.start()
    }

    func restartWatching() {
        watcher?.stop()
        watcher = nil
        startWatching()
    }

    /// Re-lists folders that changed, a moment after the last change.
    func noteChanges(_ paths: [String]) {
        let skip = scanOptions.skipFolderNames
        let rootPaths = Prefs.shared.enabledRoots.map(\.path)
        for raw in paths {
            // FSEvents reports real paths (/private/tmp…); roots may use the symlinked form (/tmp…).
            var p = raw
            if p.hasPrefix("/private/"), !rootPaths.contains(where: { p.hasPrefix($0) }) { p = String(p.dropFirst(8)) }
            let comps = p.split(separator: "/")
            if comps.contains(where: { $0.hasPrefix(".") || skip.contains(String($0)) }) { continue }
            pendingChanges.insert(p.hasSuffix("/") && p.count > 1 ? String(p.dropLast()) : p)
        }
        guard !pendingChanges.isEmpty else { return }
        changeTask?.cancel()
        changeTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            let dirs = self.pendingChanges
            self.pendingChanges.removeAll()
            await self.refresh(directories: Array(dirs))
        }
    }

    /// Updates the index for the given folders (and new subfolders inside them).
    func refresh(directories: [String]) async {
        let roots = Prefs.shared.enabledRoots
        let options = scanOptions
        let known = Set(byPath.keys)
        let results = await Task.detached(priority: .userInitiated) { () -> [(dir: String, exists: Bool, items: [FileItem])] in
            var out: [(dir: String, exists: Bool, items: [FileItem])] = []
            for dir in directories {
                guard let root = LibraryStore.root(for: dir, in: roots) else { continue }
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
                guard exists else {
                    out.append((dir: dir, exists: false, items: []))
                    continue
                }
                var listing = FileScanner.list(directory: dir, rootID: root.id, options: options)
                if root.appsOnly { listing = listing.filter { $0.kind == .app } }
                var extra: [FileItem] = []
                if !root.appsOnly {
                    for folder in listing where folder.kind == .folder && !known.contains(folder.path) {
                        let sub = IndexRoot(id: root.id, path: folder.path, name: folder.name)
                        extra += FileScanner.scan(root: sub, options: options)
                    }
                }
                out.append((dir: dir, exists: true, items: listing + extra))
            }
            return out
        }.value

        guard !results.isEmpty else { return }
        for r in results {
            if !r.exists {
                byPath.removeValue(forKey: r.dir)
                let prefix = r.dir + "/"
                for key in byPath.keys where key.hasPrefix(prefix) { byPath.removeValue(forKey: key) }
                continue
            }
            let newPaths = Set(r.items.map(\.path))
            for (key, item) in byPath where item.parentPath == r.dir && !newPaths.contains(key) {
                byPath.removeValue(forKey: key)
                if item.kind == .folder {
                    let prefix = key + "/"
                    for sub in byPath.keys where sub.hasPrefix(prefix) { byPath.removeValue(forKey: sub) }
                }
            }
            for item in r.items {
                var updated = item
                if item.kind == .app, let s = appSizes[Self.sizeKey(item)] { updated = item.withSize(s) }
                byPath[item.path] = updated
            }
        }
        let sorted = byPath.values.sorted { $0.activityDate > $1.activityDate }
        items = sorted
        version += 1
        rederive()
        scheduleSave()
        let fresh = results.flatMap(\.items)
        text.enqueue(fresh, scope: Prefs.shared.ocrScope)
        if fresh.contains(where: { $0.kind == .app && $0.size == 0 }) { measureAppSizes() }
    }

    /// Drops items that Haven itself just moved or trashed (the watcher will confirm shortly).
    func forget(paths: [String]) {
        guard !paths.isEmpty else { return }
        let set = Set(paths)
        for p in set { byPath.removeValue(forKey: p) }
        items.removeAll { set.contains($0.path) }
        version += 1
        rederive()
        duplicates.forget(paths: set)
        scheduleSave()
    }

    nonisolated static func root(for path: String, in roots: [IndexRoot]) -> IndexRoot? {
        roots.filter { path == $0.path || path.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }
    }

    func root(for path: String) -> IndexRoot? {
        Self.root(for: path, in: Prefs.shared.enabledRoots)
    }

    func item(at path: String) -> FileItem? { byPath[path] }

    // MARK: Lists for the UI

    /// Computes a list in the background. `sort` nil keeps the source's natural order (search relevance).
    func load(_ source: CollectionSource, sort: FileSortOrder?) async -> [FileItem] {
        let all = items
        let d = derived
        let lookup = text.lookup
        return await Task.detached(priority: .userInitiated) { () -> [FileItem] in
            var list: [FileItem]
            switch source {
            case .recents: list = d.recents
            case .category(let c): list = d.byCategory[c] ?? []
            case .largeFiles: list = d.largeFiles
            case .screenshots: list = d.screenshots
            case .latestDownloads: list = d.latestDownloads
            case .source(let id): list = all.filter { $0.source?.id == id && $0.kind != .folder }.sorted { $0.arrivalDate > $1.arrivalDate }
            case .query(let q):
                list = SearchEngine.search(q, in: all, text: lookup)
                if q.sort != nil { return list }
            }
            if let sort { list = sort.sorted(list) }
            return list
        }.value
    }

    /// Quick, synchronous search for Quick Search and Shortcuts.
    func search(_ text: String, limit: Int = 60) -> [FileItem] {
        let parsed = QueryParser.parse(text, customRoots: AppModel.shared.customRootWords)
        return SearchEngine.search(parsed.query, in: items, text: self.text.lookup, limit: limit)
    }

    var latestDownload: FileItem? { derived.latestDownloads.first }
}
