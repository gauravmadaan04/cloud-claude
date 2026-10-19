import Foundation

/// A folder Haven indexes.
public struct IndexRoot: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var name: String
    public var symbol: String
    /// Only look for .app bundles (two levels deep), e.g. /Applications.
    public var appsOnly: Bool
    public var isStandard: Bool
    public var enabled: Bool
    /// Desktop, Documents and Downloads are protected by macOS and need the user's OK.
    public var isProtected: Bool

    public init(id: String, path: String, name: String, symbol: String = "folder", appsOnly: Bool = false,
                isStandard: Bool = false, enabled: Bool = true, isProtected: Bool = false) {
        self.id = id
        self.path = path
        self.name = name
        self.symbol = symbol
        self.appsOnly = appsOnly
        self.isStandard = isStandard
        self.enabled = enabled
        self.isProtected = isProtected
    }

    /// The standard set under a home folder (or under a test fixture folder).
    public static func standard(home: String, applications: String = "/Applications") -> [IndexRoot] {
        func p(_ c: String) -> String { (home as NSString).appendingPathComponent(c) }
        return [
            IndexRoot(id: "desktop", path: p("Desktop"), name: "Desktop", symbol: "menubar.dock.rectangle", isStandard: true, isProtected: true),
            IndexRoot(id: "documents", path: p("Documents"), name: "Documents", symbol: "doc", isStandard: true, isProtected: true),
            IndexRoot(id: "downloads", path: p("Downloads"), name: "Downloads", symbol: "arrow.down.circle", isStandard: true, isProtected: true),
            IndexRoot(id: "pictures", path: p("Pictures"), name: "Pictures", symbol: "photo", isStandard: true),
            IndexRoot(id: "movies", path: p("Movies"), name: "Movies", symbol: "film", isStandard: true),
            IndexRoot(id: "music", path: p("Music"), name: "Music", symbol: "music.note", isStandard: true),
            IndexRoot(id: "applications", path: applications, name: "Applications", symbol: "square.grid.2x2", appsOnly: true, isStandard: true),
        ]
    }

    public static func custom(path: String) -> IndexRoot {
        IndexRoot(id: "custom:" + path, path: path, name: (path as NSString).lastPathComponent, symbol: "folder")
    }
}

public struct ScanOptions: Sendable {
    public var maxItems = 300_000
    public var maxDepth = 14
    public var skipFolderNames: Set<String> = [
        "node_modules", ".git", "Pods", "DerivedData", ".build", "__pycache__", ".venv", "venv", "site-packages",
        ".Trash", "Caches", ".npm", ".cache", "bower_components", ".gradle", "target",
    ]
    /// Honour `app.haven.test.added` (fixtures only).
    public var honorTestDates = false

    public init() {}
}

public enum FileScanner {

    static var resourceKeys: [URLResourceKey] {
        var keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .isHiddenKey,
        ]
        #if os(macOS)
        keys += [.addedToDirectoryDateKey, .tagNamesKey, .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        #endif
        return keys
    }

    /// Walks a root and returns everything Haven should show.
    public static func scan(root: IndexRoot, options: ScanOptions = ScanOptions(), progress: ((Int) -> Void)? = nil,
                            cancelled: () -> Bool = { false }) -> [FileItem] {
        let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var out: [FileItem] = []
        let enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let en = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: resourceKeys, options: enumOptions, errorHandler: { _, _ in true }) else {
            return []
        }
        let rootDepth = rootURL.standardizedFileURL.pathComponents.count
        var parentNames: [String: String] = [:]
        while let obj = en.nextObject() {
            if cancelled() { break }
            guard let url = obj as? URL else { continue }
            let name = url.lastPathComponent
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isDir = values?.isDirectory ?? false
            let isPackage = values?.isPackage ?? false
            if values?.isSymbolicLink == true { continue }
            if isDir && !isPackage {
                if options.skipFolderNames.contains(name) || name.hasSuffix(".noindex") || depth >= options.maxDepth {
                    en.skipDescendants()
                    if options.skipFolderNames.contains(name) || name.hasSuffix(".noindex") { continue }
                }
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if isPackage && KindClassifier.ignoredPackageExtensions.contains(ext) { continue }
            if root.appsOnly {
                if ext == "app" {
                    if let item = makeItem(url: url, values: values, rootID: root.id, options: options, parentNames: &parentNames) { out.append(item) }
                } else if isDir && depth >= 2 {
                    en.skipDescendants()
                }
                continue
            }
            if let item = makeItem(url: url, values: values, rootID: root.id, options: options, parentNames: &parentNames) {
                out.append(item)
                if out.count % 2_000 == 0 { progress?(out.count) }
                if out.count >= options.maxItems { break }
            }
        }
        progress?(out.count)
        return out
    }

    /// One item for a URL (used by folder listings and live updates).
    public static func item(at url: URL, rootID: String, options: ScanOptions = ScanOptions()) -> FileItem? {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        if values?.isSymbolicLink == true { return nil }
        var names: [String: String] = [:]
        return makeItem(url: url, values: values, rootID: rootID, options: options, parentNames: &names)
    }

    /// Direct children of a folder, skipping hidden files and the same folders a full scan skips.
    public static func list(directory: String, rootID: String, options: ScanOptions = ScanOptions()) -> [FileItem] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return []
        }
        var names: [String: String] = [:]
        return urls.compactMap { child in
            let ext = child.pathExtension.lowercased()
            if KindClassifier.ignoredPackageExtensions.contains(ext) { return nil }
            let values = try? child.resourceValues(forKeys: Set(resourceKeys))
            if values?.isSymbolicLink == true { return nil }
            if values?.isDirectory == true, values?.isPackage != true, isSkipped(folderNamed: child.lastPathComponent, options) { return nil }
            return makeItem(url: child, values: values, rootID: rootID, options: options, parentNames: &names)
        }
    }

    /// Folders Haven never looks inside (and doesn't list): node_modules, .git, caches, *.noindex…
    public static func isSkipped(folderNamed name: String, _ options: ScanOptions) -> Bool {
        options.skipFolderNames.contains(name) || name.hasSuffix(".noindex")
    }

    static func makeItem(url: URL, values: URLResourceValues?, rootID: String, options: ScanOptions,
                         parentNames: inout [String: String]) -> FileItem? {
        let path = url.path
        let isDir = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        if values?.isHidden == true { return nil }
        let now = Date()
        let created = values?.creationDate ?? values?.contentModificationDate ?? now
        let modified = values?.contentModificationDate ?? created
        var added: Date?
        var tags: [String] = []
        var cloudOnly = false
        #if os(macOS)
        added = values?.addedToDirectoryDate
        tags = values?.tagNames ?? []
        if values?.isUbiquitousItem == true, let status = values?.ubiquitousItemDownloadingStatus, status == .notDownloaded {
            cloudOnly = true
        }
        #endif
        let size = Int64(isDir ? 0 : (values?.fileSize ?? 0))
        let ext = (url.lastPathComponent as NSString).pathExtension.lowercased()
        let kind = KindClassifier.kind(forExtension: ext, isDirectory: isDir, isPackage: isPackage)

        var whereFroms: [String] = []
        var agent: String?
        var lastOpened: Date?
        var screenshot = false
        #if canImport(Darwin)
        if !isDir || isPackage {
            whereFroms = XAttr.whereFroms(path)
            agent = XAttr.quarantineAgent(path)
            if kind == .image || kind == .video {
                screenshot = XAttr.isScreenCapture(path)
            }
        }
        lastOpened = XAttr.lastUsedDate(path)
        if tags.isEmpty { tags = XAttr.tags(path) }
        if options.honorTestDates, let testAdded = XAttr.testAddedDate(path) {
            added = testAdded
        }
        #endif
        if !screenshot && (kind == .image || kind == .video) {
            screenshot = looksLikeScreenshotName(url.lastPathComponent)
        }
        // Files in one folder share its folded name; work it out once per folder.
        let parent = FileItem.parent(of: path)
        let parentName: String
        if let known = parentNames[parent] {
            parentName = known
        } else {
            parentName = FileItem.fold(FileItem.lastComponent(parent))
            if parentNames.count > 4_096 { parentNames.removeAll(keepingCapacity: true) }
            parentNames[parent] = parentName
        }
        return FileItem(
            path: path, name: url.lastPathComponent, kind: kind, size: size, created: created, modified: modified,
            added: added, lastOpened: lastOpened, rootID: rootID, tags: tags, whereFroms: whereFroms,
            quarantineAgent: agent, isScreenshot: screenshot, isCloudOnly: cloudOnly, searchParent: parentName
        )
    }

    /// macOS (in several languages) and popular capture tools name screenshots predictably.
    public static func looksLikeScreenshotName(_ name: String) -> Bool {
        let n = FileItem.fold(name)
        let prefixes = [
            "screenshot", "screen shot", "screen recording", "cleanshot", "capture d’ecran", "capture d'ecran",
            "bildschirmfoto", "schermata", "captura de pantalla", "schermafbeelding", "skarmavbild", "zrzut ekranu",
            "snimok ekrana", "スクリーンショット", "截屏", "屏幕快照", "shottr", "xnapper",
        ]
        return prefixes.contains { n.hasPrefix($0) }
    }

    /// Recursive size of a bundle (apps), stopping early on huge trees.
    public static func bundleSize(_ path: String, limit: Int = 400_000, cancelled: () -> Bool = { false }) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var count = 0
        while let obj = en.nextObject() as? URL {
            count += 1
            if count > limit || (count % 5_000 == 0 && cancelled()) { break }
            guard let v = try? obj.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
