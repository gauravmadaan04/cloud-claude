import AppKit
import SwiftUI
import HavenCore

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
        }
    }
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
        }
    }
    private(set) var parsed: ParsedQuery?
    var isSearching: Bool { parsed != nil }
    var searchSortOverride: FileSortOrder?
    /// Bumped to move keyboard focus into the search field (⌘F).
    var searchFocusRequest = 0

    var selectedIDs: Set<String> = []
    /// The list currently on screen (for Quick Look arrows, Select All and menu commands).
    private(set) var visibleItems: [FileItem] = []
    private(set) var visibleURLs: [URL] = []
    var sourceFilter: String?

    var quickLookURL: URL?
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
        visibleURLs = items.map(\.url)
        let ids = Set(items.map(\.id))
        if !selectedIDs.isSubset(of: ids) { selectedIDs = selectedIDs.intersection(ids) }
        if let path = pendingReveal, ids.contains(path) {
            selectedIDs = [path]
            pendingReveal = nil
        }
    }

    var selectedItems: [FileItem] {
        guard !selectedIDs.isEmpty else { return [] }
        return visibleItems.filter { selectedIDs.contains($0.id) }
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
        previewContext = list
        previewItem = item
    }

    func revealInFinder(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    /// Opens the item's folder inside Haven with the item selected.
    func showInHaven(_ item: FileItem) {
        bringMainWindowForward()
        pendingReveal = item.path
        navigate(to: .folder(item.parentPath))
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
        selectedIDs.subtract(items.map(\.id))
        if let p = previewItem, items.contains(where: { $0.id == p.id }) { previewItem = nil }
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
        let symbol = parsed?.chips.first?.symbol ?? "magnifyingglass"
        let saved = SavedSearch(name: SavedSearch.defaultName(for: text), text: text, symbol: symbol)
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
