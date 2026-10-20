import AppKit
import SwiftUI
import HavenCore
import UniformTypeIdentifiers

/// Places you can go in the main window.
enum SidebarItem: Hashable, Codable {
    case home
    case recents
    case category(LibraryCategory)
    case largeFiles
    case screenshots
    case saved(UUID)
    case sources
    case source(String)
    case duplicates
    case cleanup
    case cleanupCard(CleanupKind)
    case activity
    case folder(String)
    case space
    case collection(UUID)

    @MainActor
    var title: String {
        switch self {
        case .home: return "Home"
        case .recents: return "Recents"
        case .category(let c): return c.title
        case .largeFiles: return "Large Files"
        case .screenshots: return "Screenshots"
        case .saved(let id): return Prefs.shared.savedSearches.first { $0.id == id }?.name ?? "Saved Search"
        case .sources: return "Downloaded From"
        case .source(let id): return SourceClassifier.source(withID: id)?.name ?? "Source"
        case .duplicates: return "Duplicates"
        case .cleanup: return "Clean Up"
        case .cleanupCard(let k): return k.title
        case .activity: return "Activity"
        case .folder(let path): return FileManager.default.displayName(atPath: path)
        case .space: return "Space"
        case .collection(let id): return CollectionStore.shared.collection(id)?.name ?? "Collection"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .recents: return "clock"
        case .category(let c): return c.symbolName
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        case .screenshots: return "camera.viewfinder"
        case .saved: return "magnifyingglass"
        case .sources: return "arrow.down.circle"
        case .source: return "arrow.down.circle"
        case .duplicates: return "square.on.square"
        case .cleanup: return "sparkles"
        case .cleanupCard(let k): return k.symbolName
        case .activity: return "clock.arrow.circlepath"
        case .folder: return "folder"
        case .space: return "chart.pie"
        case .collection: return "square.stack"
        }
    }

    var accessibilityID: String {
        switch self {
        case .home: return "home"
        case .recents: return "recents"
        case .category(let c): return "category.\(c.rawValue)"
        case .largeFiles: return "largeFiles"
        case .screenshots: return "screenshots"
        case .saved(let id): return "saved.\(id.uuidString)"
        case .sources: return "sources"
        case .source(let id): return "source.\(id)"
        case .duplicates: return "duplicates"
        case .cleanup: return "cleanup"
        case .cleanupCard(let k): return "cleanup.\(k.rawValue)"
        case .activity: return "activity"
        case .folder(let p): return "folder.\((p as NSString).lastPathComponent)"
        case .space: return "space"
        case .collection(let id): return "collection.\(id.uuidString)"
        }
    }
}

/// Files the rename sheet is open for.
struct RenameRequest: Identifiable {
    let id = UUID()
    let items: [FileItem]
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    var undoEntry: UUID?
}

/// UI state shared by the main window, menus, Quick Search and the menu bar.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var selection: SidebarItem? = .home {
        didSet {
            guard selection != oldValue else { return }
            if !isNavigatingHistory, let old = oldValue {
                backStack.append(old)
                if backStack.count > 50 { backStack.removeFirst() }
                forwardStack.removeAll()
            }
            selectedIDs = []
            sourceFilter = nil
            if searchText.isEmpty == false && !keepSearchOnNavigate { searchText = "" }
            pageSortOverride = nil
            pendingReveal = nil
            // Going somewhere else ends typing in the search box (and closes its suggestions).
            SearchFieldBridge.shared.resign()
        }
    }
    private(set) var backStack: [SidebarItem] = []
    private(set) var forwardStack: [SidebarItem] = []
    @ObservationIgnored private var isNavigatingHistory = false
    @ObservationIgnored private var keepSearchOnNavigate = false

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            parsed = trimmed.isEmpty ? nil : QueryParser.parse(trimmed, customRoots: customRootWords)
            searchSortOverride = nil
            selectedIDs = []
            rememberTask?.cancel()
            if !trimmed.isEmpty {
                rememberTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    if !Task.isCancelled { Prefs.shared.rememberSearch(trimmed) }
                }
            }
        }
    }
    @ObservationIgnored private var rememberTask: Task<Void, Never>?
    /// The toolbar search field has keyboard focus (shows suggestions while it's empty).
    var searchFieldFocused = false
    private(set) var parsed: ParsedQuery?
    var isSearching: Bool { parsed != nil }
    var searchSortOverride: FileSortOrder?
    /// Bumped to move keyboard focus into the search field (⌘F).
    var searchFocusRequest = 0
    /// Bumped to move keyboard focus from the search field into the results (↓ or ↩ in the field).
    var focusResultsRequest = 0

    var selectedIDs: Set<String> = [] { didSet { selectionVersion &+= 1 } }
    /// The list currently on screen (for Quick Look arrows, Select All and menu commands).
    private(set) var visibleItems: [FileItem] = [] { didSet { selectionVersion &+= 1 } }
    /// Files Quick Look can step through: built only while Quick Look is open, around the current file.
    private(set) var quickLookURLs: [URL] = []
    @ObservationIgnored private var selectionVersion = 0
    @ObservationIgnored private var selectedCache: (version: Int, items: [FileItem]) = (-1, [])
    /// Bumped when a file should be scrolled into view (Show in Haven).
    var revealRequest = 0
    /// Pages with their own order (Large Files: biggest first) keep it until you pick another sort there.
    var pageSortOverride: FileSortOrder?
    var sourceFilter: String?

    var quickLookURL: URL? {
        didSet {
            guard let url = quickLookURL else { quickLookURLs = []; return }
            if !quickLookURLs.contains(url) { quickLookURLs = Self.window(around: url, in: visibleItems) }
        }
    }
    var previewItem: FileItem?
    /// The list the large preview steps through with the arrow keys (defaults to the visible list).
    var previewContext: [FileItem] = []
    var showInspector = false
    var showOnboarding = false
    var showShortcuts = false
    var showSearchTips = false
    var toast: Toast?
    /// Path to select once a folder view has loaded ("Show in Haven").
    var pendingReveal: String?
    /// Files to select once they show up in the list (just renamed, or copies just made).
    @ObservationIgnored var pendingSelection: Set<String> = []
    var renameRequest: RenameRequest?
    /// Explains the Accessibility permission the Open/Save jump needs.
    var showDialogJumpHelp = false
    /// The rule being made or changed in the rule editor.
    var editingRule: CustomRule?

    @ObservationIgnored var openWindowAction: OpenWindowAction?
    @ObservationIgnored var openSettingsAction: OpenSettingsAction?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private init() {
        let opts = LaunchOptions.current
        showOnboarding = !(Prefs.shared.onboardingDone || opts.skipOnboarding)
    }

    var customRootWords: [String: String] {
        var map: [String: String] = [:]
        for root in Prefs.shared.roots where !root.isStandard {
            map[FileItem.fold(root.name)] = root.id
        }
        return map
    }

    // MARK: Navigation

    func navigate(to item: SidebarItem, keepSearch: Bool = false) {
        keepSearchOnNavigate = keepSearch
        if searchText.isEmpty == false && !keepSearch { searchText = "" }
        selection = item
        keepSearchOnNavigate = false
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        if isSearching { searchText = ""; return }
        guard let prev = backStack.popLast() else { return }
        if let current = selection { forwardStack.append(current) }
        isNavigatingHistory = true
        selection = prev
        isNavigatingHistory = false
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selection { backStack.append(current) }
        isNavigatingHistory = true
        selection = next
        isNavigatingHistory = false
    }

    // MARK: Visible list & selection

    func setVisible(_ items: [FileItem]) {
        visibleItems = items
        if let url = quickLookURL { quickLookURLs = Self.window(around: url, in: items) }
        if !pendingSelection.isEmpty {
            let arrived = Self.present(pendingSelection, in: items)
            if !arrived.isEmpty {
                selectedIDs = arrived
                pendingSelection.subtract(arrived)
                if let first = items.first(where: { arrived.contains($0.id) }) {
                    selectionAnchor = first.id
                    selectionLead = first.id
                    reveal(first.id, centered: true)
                }
                return
            }
        }
        if let path = pendingReveal, !Self.present([path], in: items).isEmpty {
            selectedIDs = [path]
            selectionAnchor = path
            selectionLead = path
            pendingReveal = nil
            reveal(path, centered: true)
            return
        }
        guard !selectedIDs.isEmpty else { return }
        let still = Self.present(selectedIDs, in: items)
        if still.count != selectedIDs.count { selectedIDs = still }
    }

    /// Which of these paths are in the list. Comparing lengths first skips hashing nearly every file.
    static func present(_ ids: Set<String>, in items: [FileItem]) -> Set<String> {
        let lengths = Set(ids.map(\.utf8.count))
        var found = Set<String>()
        for item in items where lengths.contains(item.path.utf8.count) && ids.contains(item.path) {
            found.insert(item.path)
            if found.count == ids.count { break }
        }
        return found
    }

    /// Up to a thousand files around `url`, for Quick Look's arrows (URLs are cheap, but not 300,000 of them).
    static func window(around url: URL, in items: [FileItem]) -> [URL] {
        let path = url.path
        let i = items.firstIndex { $0.path == path } ?? 0
        let lo = max(0, i - 500)
        let hi = min(items.count, i + 500)
        var urls = items[lo..<hi].map(\.url)
        if !urls.contains(url) { urls.insert(url, at: 0) }
        return urls
    }

    var selectedItems: [FileItem] {
        guard !selectedIDs.isEmpty else { return [] }
        if selectedCache.version == selectionVersion { return selectedCache.items }
        let ids = selectedIDs
        let lengths = Set(ids.map(\.utf8.count))
        let items = visibleItems.filter { lengths.contains($0.path.utf8.count) && ids.contains($0.path) }
        selectedCache = (selectionVersion, items)
        return items
    }

    // MARK: Sorting

    static func naturalSort(for item: SidebarItem?) -> FileSortOrder? {
        item == .largeFiles ? .sizeLargest : nil
    }

    /// The order the current page uses.
    var pageSort: FileSortOrder { pageSortOverride ?? Self.naturalSort(for: selection) ?? Prefs.shared.sortOrder }

    /// The sort shown as active: nil means best match (search without a picked sort).
    var activeSort: FileSortOrder? { isSearching ? searchSortOverride : pageSort }

    func pickSort(_ order: FileSortOrder?) {
        if isSearching {
            searchSortOverride = order
        } else if let order {
            if Self.naturalSort(for: selection) != nil { pageSortOverride = order } else { Prefs.shared.sortOrder = order }
        }
    }

    var firstSelected: FileItem? {
        if let p = previewItem { return p }
        return selectedItems.first
    }

    func selectAll() { selectedIDs = Set(visibleItems.map(\.id)) }

    // MARK: Actions on files

    func open(_ items: [FileItem]) {
        for item in items {
            if item.kind == .folder {
                navigate(to: .folder(item.path))
                return
            }
            if item.kind == .audio {
                MusicPlayer.shared.play(item, queue: visibleItems.filter { $0.kind == .audio })
                continue
            }
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Double-click: preview or open, as chosen in Settings. Folders always open in Haven.
    func activate(_ item: FileItem) {
        if item.kind == .folder { navigate(to: .folder(item.path)); return }
        if item.kind == .audio { MusicPlayer.shared.play(item, queue: visibleItems.filter { $0.kind == .audio }); return }
        if item.kind == .app { NSWorkspace.shared.open(item.url); return }
        switch Prefs.shared.doubleClick {
        case .preview: preview(item, in: visibleItems)
        case .open: NSWorkspace.shared.open(item.url)
        }
    }

    func preview(_ item: FileItem, in list: [FileItem]) {
        SearchFieldBridge.shared.resign()
        previewContext = list
        previewItem = item
    }

    var isPreviewing: Bool { previewItem != nil }

    func closePreview() {
        withAnimation(.easeOut(duration: 0.18)) {
            previewItem = nil
            previewContext = []
        }
    }

    /// ←/→ in the large preview.
    func stepPreview(_ delta: Int) {
        let list = previewContext.isEmpty ? visibleItems : previewContext
        guard let current = previewItem, let i = list.firstIndex(where: { $0.id == current.id }) else { return }
        let next = i + delta
        guard list.indices.contains(next) else { return }
        previewItem = list[next]
        selectedIDs = [list[next].id]
    }

    func revealInFinder(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    /// Opens the item's folder inside Haven with the item selected and scrolled into view.
    func showInHaven(_ item: FileItem) {
        bringMainWindowForward()
        let folder = SidebarItem.folder(item.parentPath)
        if selection == folder && !isSearching {
            // Already there: select it right away (a pending reveal would never be used).
            pendingReveal = nil
            selectedIDs = [item.id]
            selectionAnchor = item.id
            selectionLead = item.id
            reveal(item.id, centered: true)
        } else {
            navigate(to: folder)
            pendingReveal = item.path
        }
    }

    func toggleQuickLook() {
        if quickLookURL != nil {
            quickLookURL = nil
        } else if let item = selectedItems.first ?? visibleItems.first {
            if selectedIDs.isEmpty { selectedIDs = [item.id] }
            quickLookURL = item.url
        }
    }

    func copyFiles(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        showToast(items.count == 1 ? "Copied “\(items[0].name)”" : "Copied \(items.count) files", symbol: "doc.on.doc")
    }

    func copyPaths(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
        showToast(items.count == 1 ? "Copied path" : "Copied \(items.count) paths", symbol: "link")
    }

    func copyText(_ items: [FileItem]) {
        let readable = items.filter { $0.kind.hasReadableText }
        guard !readable.isEmpty else {
            showToast("No text to copy here", symbol: "text.badge.xmark")
            return
        }
        Task {
            var parts: [String] = []
            for item in readable {
                if let t = await LibraryStore.shared.text.text(for: item), !t.isEmpty { parts.append(t) }
            }
            let joined = parts.joined(separator: "\n\n")
            if joined.isEmpty {
                showToast("Haven didn't find any text", symbol: "text.badge.xmark")
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(joined, forType: .string)
                let words = joined.split { $0.isWhitespace }.count
                showToast("Copied text (\(HavenFormat.count(words, "word")))", symbol: "text.quote")
            }
        }
    }

    func trash(_ items: [FileItem], reason: String, undoManager: UndoManager? = nil) {
        guard !items.isEmpty else { return }
        FileOps.shared.trash(items, reason: reason, undoManager: undoManager)
        let ids = Set(items.map(\.id))
        selectedIDs.subtract(ids)
        // The large preview steps over what's gone.
        if !previewContext.isEmpty { previewContext.removeAll { ids.contains($0.id) } }
        if let p = previewItem, ids.contains(p.id) { previewItem = nil }
    }

    @ObservationIgnored private var typedName = ""
    @ObservationIgnored private var typedAt = Date.distantPast
    /// Where a ⇧-click or ⇧-arrow selection starts, and the file at its moving end.
    @ObservationIgnored var selectionAnchor: String?
    @ObservationIgnored var selectionLead: String?
    /// Columns in the grid on screen (for ↑/↓).
    @ObservationIgnored var gridColumns = 1
    /// How many file grids/lists are on screen (browser keys only act on those pages).
    @ObservationIgnored var fileListsOnScreen = 0
    /// The file the list should scroll to on the next `revealRequest`.
    @ObservationIgnored private(set) var scrollTarget: (id: String, centered: Bool)?

    enum MoveDirection { case left, right, up, down }

    /// Scrolls the list on screen to a file (centred for jumps, just into view for arrow keys).
    func reveal(_ id: String, centered: Bool) {
        scrollTarget = (id, centered)
        revealRequest += 1
    }

    private func index(of id: String?, in list: [FileItem]) -> Int? {
        guard let id else { return nil }
        let length = id.utf8.count
        return list.firstIndex { $0.path.utf8.count == length && $0.path == id }
    }

    /// Arrow keys: move the selection; with ⇧ grow or shrink it from where it started.
    @discardableResult
    func moveSelection(_ direction: MoveDirection, extend: Bool) -> Bool {
        let list = visibleItems
        guard !list.isEmpty, !isPreviewing else { return false }
        let isGrid = Prefs.shared.viewMode == .grid
        let step: Int
        switch direction {
        case .left: step = isGrid ? -1 : 0
        case .right: step = isGrid ? 1 : 0
        case .up: step = isGrid ? -max(1, gridColumns) : -1
        case .down: step = isGrid ? max(1, gridColumns) : 1
        }
        guard step != 0 else { return false }
        let from = index(of: selectionLead, in: list) ?? index(of: selectionAnchor, in: list)
            ?? list.firstIndex { selectedIDs.contains($0.id) }
        let next = from.map { max(0, min(list.count - 1, $0 + step)) } ?? 0
        let target = list[next]
        if extend, let a = index(of: selectionAnchor, in: list) {
            let range = a <= next ? a...next : next...a
            selectedIDs = Set(list[range].map(\.id))
        } else {
            selectedIDs = [target.id]
            selectionAnchor = target.id
        }
        selectionLead = target.id
        reveal(target.id, centered: false)
        if quickLookURL != nil { quickLookURL = target.url }
        return true
    }

    /// Typing the start of a name selects the first file (in name order) that begins with it, like Finder.
    /// Keys typed within a second and a half of each other add up ("inv" → invoice.pdf).
    @discardableResult
    func typeAhead(_ characters: String) -> Bool {
        guard !visibleItems.isEmpty, !isPreviewing, !characters.isEmpty else { return false }
        let now = Date()
        typedName = now.timeIntervalSince(typedAt) > 1.5 ? characters : typedName + characters
        typedAt = now
        let prefix = Array(FileItem.fold(typedName).utf8)
        var best: FileItem?
        var bestKey: [UInt8] = []
        for item in visibleItems where TextMatch.starts(with: prefix, item.searchName) {
            let key = NaturalOrder.key(item.searchName)
            if best == nil || NaturalOrder.compare(key, bestKey) < 0 {
                best = item
                bestKey = key
            }
        }
        guard let hit = best else { return true }
        selectedIDs = [hit.id]
        selectionAnchor = hit.id
        selectionLead = hit.id
        reveal(hit.id, centered: true)
        if quickLookURL != nil { quickLookURL = hit.url }
        return true
    }

    /// ⌘↑: the folder that contains the one on screen (up to the top of an indexed folder).
    @discardableResult
    func goToEnclosingFolder() -> Bool {
        guard !isSearching, case .folder(let path)? = selection,
              let root = LibraryStore.shared.root(for: path), path != root.path else { return false }
        let child = path
        navigate(to: .folder(FileItem.parent(of: path)))
        pendingReveal = child
        return true
    }

    /// ⌘V in a folder: copies the files on the clipboard into it.
    @discardableResult
    func pasteFiles() -> Bool {
        guard !isSearching, case .folder(let dir)? = selection else { return false }
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        FileOps.shared.copy(urls, into: dir)
        return true
    }

    // MARK: Rename, collections, shelf, sharing

    func rename(_ items: [FileItem]) {
        let usable = items.filter { $0.kind != .app || items.count == 1 }
        guard !usable.isEmpty else { return }
        bringMainWindowForward()
        renameRequest = RenameRequest(items: usable)
    }

    func addToCollection(_ items: [FileItem], _ id: UUID) {
        let added = CollectionStore.shared.add(items.map(\.path), to: id)
        let name = CollectionStore.shared.collection(id)?.name ?? "the collection"
        showToast(added == 0 ? "Already in “\(name)”" : (added == 1 ? "Added to “\(name)”" : "Added \(added) files to “\(name)”"),
                  symbol: "square.stack")
    }

    func newCollection(with items: [FileItem]) {
        let id = CollectionStore.shared.create(name: nil, paths: items.map(\.path))
        navigate(to: .collection(id))
        showToast(items.isEmpty ? "New collection" : "Made a collection of \(HavenFormat.count(items.count, "file"))", symbol: "square.stack")
    }

    func removeFromCollection(_ items: [FileItem], _ id: UUID) {
        CollectionStore.shared.remove(Set(items.map(\.path)), from: id)
        selectedIDs.subtract(items.map(\.id))
    }

    func addToShelf(_ items: [FileItem]) {
        ShelfStore.shared.add(items.map(\.url))
        ShelfController.shared.show()
    }

    func makeShareable(_ kind: ShareNaming.Kind, _ items: [FileItem]) {
        ShareMaker.shared.run(kind, items: items, undoManager: AppModel.mainWindow?.undoManager)
    }

    /// The visible list (or the selected files in it) as text on the clipboard.
    func copyList(_ format: ListExport.Format, _ items: [FileItem]) {
        guard !items.isEmpty else { return }
        // Big lists are written out in the background.
        guard items.count < 20_000 else {
            Task {
                let text = await Task.detached(priority: .userInitiated) { ListExport.text(items, format: format) }.value
                self.putOnClipboard(text, format, count: items.count)
            }
            return
        }
        putOnClipboard(ListExport.text(items, format: format), format, count: items.count)
    }

    private func putOnClipboard(_ text: String, _ format: ListExport.Format, count: Int) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        let what: String
        switch format {
        case .names: what = count == 1 ? "Copied the name" : "Copied \(count) names"
        case .paths: what = count == 1 ? "Copied the path" : "Copied \(count) paths"
        case .table, .csv: what = "Copied a table of \(HavenFormat.count(count, "file")): paste it into Numbers or Excel"
        }
        showToast(what, symbol: "list.bullet.rectangle")
    }

    func exportCSV(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selection?.title ?? "Files").csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                let text = ListExport.text(items, format: .csv)
                return (try? Data(text.utf8).write(to: url, options: .atomic)) != nil
            }.value
            showToast(ok ? "Saved “\(url.lastPathComponent)”" : "Couldn't save the list", symbol: ok ? "tablecells" : "exclamationmark.triangle")
        }
    }

    func togglePin(_ path: String) {
        if let i = Prefs.shared.pinnedFolders.firstIndex(of: path) {
            Prefs.shared.pinnedFolders.remove(at: i)
        } else {
            Prefs.shared.pinnedFolders.append(path)
            showToast("Pinned to the sidebar", symbol: "pin")
        }
    }

    // MARK: Saved searches

    func saveCurrentSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let existing = Prefs.shared.savedSearches.first(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame }) {
            navigate(to: .saved(existing.id))
            return
        }
        let saved = SavedSearch(name: SavedSearch.defaultName(for: text), text: text, symbol: "bookmark")
        Prefs.shared.savedSearches.append(saved)
        navigate(to: .saved(saved.id))
        showToast("Saved to the sidebar", symbol: "bookmark")
    }

    func deleteSavedSearch(_ id: UUID) {
        Prefs.shared.savedSearches.removeAll { $0.id == id }
        if selection == .saved(id) { selection = .home }
    }

    // MARK: Look & size

    func toggleLook() {
        Prefs.shared.look = Prefs.shared.look == .playful ? .minimal : .playful
    }

    func bigger() { Prefs.shared.cardSize = min(320, Prefs.shared.cardSize + 24) }
    func smaller() { Prefs.shared.cardSize = max(110, Prefs.shared.cardSize - 24) }

    // MARK: Toasts

    func showToast(_ message: String, symbol: String = "checkmark.circle", undoEntry: UUID? = nil) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = Toast(message: message, symbol: symbol, undoEntry: undoEntry) }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undoEntry == nil ? 2.5 : 7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: Windows

    func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = AppModel.mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else if let open = openWindowAction {
            open(id: "main")
        }
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let open = openSettingsAction {
            open()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func replayOnboarding() {
        bringMainWindowForward()
        withAnimation(.easeInOut) { showOnboarding = true }
    }
}
