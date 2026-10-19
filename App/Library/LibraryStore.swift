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
/// Everything heavy (reading the saved index, scanning, merging changes, saving) happens off the main thread.
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

    @ObservationIgnored private var watcher: FSWatcher?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var deriveTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    /// Folders to re-list, and folders whose whole subtree must be read again.
    @ObservationIgnored private var pendingChanges = Set<String>()
    @ObservationIgnored private var pendingDeep = Set<String>()
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var appSizes: [String: Int64] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var duplicatesRunThisLaunch = false
    /// Bumped whenever the whole index is replaced; work started on an older index is redone.
    @ObservationIgnored private var generation = 0
    /// Paths Haven moved or trashed, numbered, so results computed from an older index can drop them.
    @ObservationIgnored private var forgetLog: [(seq: Int, paths: Set<String>)] = []
    @ObservationIgnored private var forgetSeq = 0
    /// Folders that changed while a full scan ran; re-listed once its result lands.
    @ObservationIgnored private var changedDuringScan = Set<String>()

    private init() {}

    var scanOptions: ScanOptions {
        var o = ScanOptions()
        o.honorTestDates = LaunchOptions.current.isFixtureMode
        return o
    }

    private var supportDir: URL { LaunchOptions.current.supportDirectory }
    private var snapshotURL: URL { supportDir.appendingPathComponent("index.bin") }
    /// Haven 1.0 saved the index as JSON; it's read once if there's no binary index yet.
    private var legacySnapshotURL: URL { supportDir.appendingPathComponent("index.json") }
    private var appSizesURL: URL { supportDir.appendingPathComponent("app-sizes.json") }

    // MARK: Start-up

    func start() {
        guard !started else { return }
        started = true
        let binURL = snapshotURL
        let jsonURL = legacySnapshotURL
        let sizesURL = appSizesURL
        let enabledIDs = Set(Prefs.shared.enabledRoots.map(\.id))
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> ([FileItem], [String: Int64]) in
                let items = LibraryStore.readIndex(bin: binURL, json: jsonURL).filter { enabledIDs.contains($0.rootID) }
                var sizes: [String: Int64] = [:]
                if let d = try? Data(contentsOf: sizesURL), let s = try? JSONDecoder().decode([String: Int64].self, from: d) {
                    sizes = s
                }
                return (FileSortOrder.dateNewest.sorted(items), sizes)
            }.value
            self.appSizes = loaded.1
            if !loaded.0.isEmpty { self.replaceAll(loaded.0, fromSnapshot: true) }
            await self.text.load()
            await self.duplicates.loadCache()
            self.rescan()
            self.startWatching()
        }
    }

    nonisolated static func readIndex(bin: URL, json: URL) -> [FileItem] {
        if let d = try? Data(contentsOf: bin, options: .mappedIfSafe), let snap = try? IndexCodec.decode(d) {
            return snap.items
        }
        if let d = try? Data(contentsOf: json), let snap = try? JSONDecoder().decode(IndexSnapshot.self, from: d),
           snap.version == IndexSnapshot.currentVersion {
            return snap.items
        }
        return []
    }

    // MARK: Scanning

    /// Reads every folder again, each root on its own core.
    func rescan() {
        scanTask?.cancel()
        let roots = Prefs.shared.enabledRoots
        let options = scanOptions
        let sizes = appSizes
        let startSeq = forgetSeq
        isScanning = true
        scanCount = 0
        changedDuringScan = []
        let store = self
        scanTask = Task.detached(priority: .utility) {
            let progress = ScanProgress(roots: roots.count) { total in
                Task { @MainActor in if store.isScanning { store.scanCount = total } }
            }
            let cancel = CancelFlag()
            let found = await withTaskCancellationHandler {
                LibraryStore.scanAll(roots, options: options, progress: progress, cancel: cancel)
            } onCancel: {
                cancel.set()
            }
            if cancel.isSet { return }
            let sorted = FileSortOrder.dateNewest.sorted(found.map { LibraryStore.withAppSize($0, sizes) })
            await MainActor.run { store.finishScan(sorted, startSeq: startSeq) }
        }
    }

    nonisolated static func scanAll(_ roots: [IndexRoot], options: ScanOptions, progress: ScanProgress, cancel: CancelFlag) -> [FileItem] {
        var results = [[FileItem]](repeating: [], count: roots.count)
        results.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: roots.count) { i in
                out[i] = FileScanner.scan(root: roots[i], options: options,
                                          progress: { n in progress.update(root: i, count: n) },
                                          cancelled: { cancel.isSet })
            }
        }
        // A custom folder inside a standard one would be found twice.
        let overlapping = roots.contains { a in roots.contains { b in a.id != b.id && a.path.hasPrefix(b.path + "/") } }
        guard overlapping else { return results.flatMap { $0 } }
        var seen = Set<String>()
        var all: [FileItem] = []
        for r in results { for item in r where seen.insert(item.path).inserted { all.append(item) } }
        return all
    }

    private func finishScan(_ scanned: [FileItem], startSeq: Int) {
        let forgotten = forgottenSince(startSeq)
        replaceAll(forgotten.isEmpty ? scanned : IndexMerge.removing(forgotten, from: scanned), fromSnapshot: false)
        isScanning = false
        lastScan = Date()
        scheduleSave()
        measureAppSizes()
        RulesRunner.shared.runIfDue()
        if !changedDuringScan.isEmpty {
            // Changes that happened mid-scan may be missing from its result.
            pendingChanges.formUnion(changedDuringScan)
            changedDuringScan = []
            Task { await self.drainChanges() }
        }
        trimForgetLog()
    }

    private func replaceAll(_ newItems: [FileItem], fromSnapshot: Bool) {
        items = newItems
        generation += 1
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

    /// Saves the index a few seconds after the last change, in the background.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        let roots = Prefs.shared.enabledRoots.map(\.path)
        let url = snapshotURL
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(6))
            if Task.isCancelled { return }
            let data = IndexCodec.encode(items: snapshot, rootPaths: roots)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: App sizes

    nonisolated static func sizeKey(_ item: FileItem) -> String {
        "\(item.path)|\(Int(item.modified.timeIntervalSince1970))"
    }

    nonisolated static func withAppSize(_ item: FileItem, _ sizes: [String: Int64]) -> FileItem {
        guard item.kind == .app, item.size == 0, let s = sizes[sizeKey(item)] else { return item }
        return item.withSize(s)
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
        let sized = items.map { item -> FileItem in
            let updated = LibraryStore.withAppSize(item, results)
            if updated !== item { changed = true }
            return updated
        }
        if changed {
            items = sized
            generation += 1
            version += 1
            rederive()
            scheduleSave()
        }
        let sizes = appSizes
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(sizes) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Live updates

    private func startWatching() {
        let paths = Prefs.shared.enabledRoots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        let store = self
        watcher = FSWatcher(paths: paths) { changed, deep, rootChanged in
            Task { @MainActor in
                if rootChanged { store.rescan() } else { store.noteChanges(changed, deep: deep) }
            }
        }
        watcher?.start()
    }

    func restartWatching() {
        watcher?.stop()
        watcher = nil
        startWatching()
    }

    /// Re-lists folders that changed, a moment after the last change. `deep` folders are read again in full
    /// (macOS asks for that when it dropped events for them).
    func noteChanges(_ paths: [String], deep: [String] = []) {
        let skip = scanOptions.skipFolderNames
        let rootPaths = Prefs.shared.enabledRoots.map(\.path)
        func normalized(_ raw: String) -> String? {
            // FSEvents reports real paths (/private/tmp…); roots may use the symlinked form (/tmp…).
            var p = raw
            if p.hasPrefix("/private/"), !rootPaths.contains(where: { p.hasPrefix($0) }) { p = String(p.dropFirst(8)) }
            let comps = p.split(separator: "/")
            if comps.contains(where: { $0.hasPrefix(".") || skip.contains(String($0)) || $0.hasSuffix(".noindex") }) { return nil }
            return p.hasSuffix("/") && p.count > 1 ? String(p.dropLast()) : p
        }
        for raw in paths { if let p = normalized(raw) { pendingChanges.insert(p) } }
        for raw in deep { if let p = normalized(raw) { pendingDeep.insert(p) } }
        guard !pendingChanges.isEmpty || !pendingDeep.isEmpty else { return }
        changeTask?.cancel()
        changeTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self.drainChanges()
        }
    }

    /// Updates the index for the given folders (and new subfolders inside them).
    func refresh(directories: [String]) async {
        pendingChanges.formUnion(directories)
        await drainChanges()
    }

    /// Works through queued folder changes one batch at a time, off the main thread.
    private func drainChanges() async {
        guard !isRefreshing else { return } // the running loop picks new changes up
        isRefreshing = true
        defer {
            isRefreshing = false
            trimForgetLog()
        }
        while !pendingChanges.isEmpty || !pendingDeep.isEmpty {
            let dirs = Array(pendingChanges)
            let deep = Array(pendingDeep)
            pendingChanges.removeAll()
            pendingDeep.removeAll()
            if isScanning { changedDuringScan.formUnion(dirs + deep) }
            let base = items
            let startGeneration = generation
            let startSeq = forgetSeq
            let roots = Prefs.shared.enabledRoots
            let options = scanOptions
            let sizes = appSizes
            let result = await Task.detached(priority: .userInitiated) {
                LibraryStore.relist(dirs, deep: deep, base: base, roots: roots, options: options, sizes: sizes)
            }.value
            guard startGeneration == generation else {
                // The whole index was replaced meanwhile: do these folders again on top of it.
                pendingChanges.formUnion(dirs)
                pendingDeep.formUnion(deep)
                continue
            }
            let forgotten = forgottenSince(startSeq)
            items = forgotten.isEmpty ? result.items : IndexMerge.removing(forgotten, from: result.items)
            version += 1
            rederive()
            scheduleSave()
            text.enqueue(result.fresh, scope: Prefs.shared.ocrScope)
            if result.fresh.contains(where: { $0.kind == .app && $0.size == 0 }) { measureAppSizes() }
        }
    }

    nonisolated static func relist(_ dirs: [String], deep: [String], base: [FileItem], roots: [IndexRoot],
                                   options: ScanOptions, sizes: [String: Int64]) -> (items: [FileItem], fresh: [FileItem]) {
        var listed: [String: [FileItem]] = [:]
        var gone: [String] = []
        var added: [FileItem] = []
        var knownFolders: Set<String>?
        let fm = FileManager.default
        for dir in dirs {
            guard let root = root(for: dir, in: roots) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                gone.append(dir)
                continue
            }
            var listing = FileScanner.list(directory: dir, rootID: root.id, options: options)
            if root.appsOnly { listing = listing.filter { $0.kind == .app } }
            listing = listing.map { withAppSize($0, sizes) }
            if !root.appsOnly {
                let folders = listing.filter { $0.kind == .folder }
                if !folders.isEmpty {
                    if knownFolders == nil { knownFolders = Set(base.lazy.filter { $0.kind == .folder }.map(\.path)) }
                    for folder in folders where !knownFolders!.contains(folder.path) {
                        let sub = IndexRoot(id: root.id, path: folder.path, name: folder.name)
                        added += FileScanner.scan(root: sub, options: options).map { withAppSize($0, sizes) }
                    }
                }
            }
            listed[dir] = listing
        }
        for dir in deep {
            guard let root = root(for: dir, in: roots) else { continue }
            gone.append(dir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
            if dir != root.path, let me = FileScanner.item(at: URL(fileURLWithPath: dir, isDirectory: true), rootID: root.id, options: options) {
                added.append(me)
            }
            let sub = IndexRoot(id: root.id, path: dir, name: (dir as NSString).lastPathComponent, appsOnly: root.appsOnly)
            added += FileScanner.scan(root: sub, options: options).map { withAppSize($0, sizes) }
        }
        let merged = IndexMerge.apply(base: base, listed: listed, gone: gone, added: added)
        return (merged, listed.values.flatMap { $0 } + added)
    }

    /// Drops items that Haven itself just moved or trashed (the watcher will confirm shortly).
    func forget(paths: [String]) {
        guard !paths.isEmpty else { return }
        let set = Set(paths)
        forgetSeq += 1
        forgetLog.append((forgetSeq, set))
        items = IndexMerge.removing(set, from: items)
        version += 1
        rederive()
        duplicates.forget(paths: set)
        scheduleSave()
    }

    private func forgottenSince(_ seq: Int) -> Set<String> {
        var out = Set<String>()
        for entry in forgetLog where entry.seq > seq { out.formUnion(entry.paths) }
        return out
    }

    private func trimForgetLog() {
        if !isScanning && !isRefreshing { forgetLog.removeAll() }
    }

    nonisolated static func root(for path: String, in roots: [IndexRoot]) -> IndexRoot? {
        roots.filter { path == $0.path || path.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }
    }

    func root(for path: String) -> IndexRoot? {
        Self.root(for: path, in: Prefs.shared.enabledRoots)
    }

    // MARK: Lists for the UI

    /// Computes a list in the background and stops early when the caller goes away (a new keystroke).
    /// `sort` nil keeps the source's own order (search relevance, or the query's "largest", "oldest"…).
    func load(_ source: CollectionSource, sort: FileSortOrder?) async -> [FileItem] {
        let all = items
        let d = derived
        let lookup = text.lookup
        let job = Task.detached(priority: .userInitiated) { () -> [FileItem] in
            let cancel = CancelFlag()
            return await withTaskCancellationHandler { () -> [FileItem] in
                var list: [FileItem]
                switch source {
                case .recents: list = d.recents
                case .category(let c): list = d.byCategory[c] ?? []
                case .largeFiles: list = d.largeFiles
                case .screenshots: list = d.screenshots
                case .latestDownloads: list = d.latestDownloads
                case .source(let id):
                    list = all.filter { $0.source?.id == id && $0.kind != .folder }
                    list = FileSortOrder.ordered(list, list.map { $0.arrivalDate.timeIntervalSinceReferenceDate }, descending: true)
                case .query(let q):
                    list = SearchEngine.search(q, in: all, text: lookup, isCancelled: { cancel.isSet })
                }
                if cancel.isSet { return [] }
                if let sort { list = sort.sorted(list) }
                return list
            } onCancel: {
                cancel.set()
            }
        }
        return await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
    }

    /// Quick search for Shortcuts and the menu bar.
    func search(_ text: String, limit: Int = 60) -> [FileItem] {
        let parsed = QueryParser.parse(text, customRoots: AppModel.shared.customRootWords)
        return SearchEngine.search(parsed.query, in: items, text: self.text.lookup, limit: limit)
    }

    var latestDownload: FileItem? { derived.latestDownloads.first }
}

/// A cancel switch background loops can check from any thread.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); value = true; lock.unlock()
    }
}

/// Adds up files found per root while roots are scanned in parallel.
final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int]
    private let report: (Int) -> Void

    init(roots: Int, report: @escaping (Int) -> Void) {
        counts = Array(repeating: 0, count: roots)
        self.report = report
    }

    func update(root: Int, count: Int) {
        lock.lock()
        counts[root] = count
        let total = counts.reduce(0, +)
        lock.unlock()
        report(total)
    }
}
