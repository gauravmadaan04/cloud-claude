import Foundation

/// One file or folder Haven knows about. Value type, cheap to copy, safe to pass between threads.
public struct FileItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }

    public let path: String
    public let name: String
    /// Lowercased extension without the dot ("" when there is none).
    public let ext: String
    public let kind: FileKind
    /// Logical size in bytes (for apps: the bundle size once measured, else 0).
    public var size: Int64
    public let created: Date
    public let modified: Date
    /// When the file arrived in its folder (download time for Downloads).
    public let added: Date?
    /// When the file was last opened (from `com.apple.lastuseddate#PS`).
    public let lastOpened: Date?
    /// Id of the index root the file was found under ("downloads", "desktop", a custom path…).
    public let rootID: String
    public let tags: [String]
    public let whereFroms: [String]
    public let quarantineAgent: String?
    public let isScreenshot: Bool
    /// Stored only in iCloud (not downloaded): never read, hashed or OCR'd, so nothing downloads.
    public let isCloudOnly: Bool
    public let source: DownloadSource?
    /// Lowercased, accent-folded name used by search.
    public let searchName: String
    /// Lowercased, accent-folded name of the enclosing folder (searched too).
    public let searchParent: String

    public init(
        path: String,
        name: String? = nil,
        kind: FileKind? = nil,
        size: Int64 = 0,
        created: Date,
        modified: Date,
        added: Date? = nil,
        lastOpened: Date? = nil,
        rootID: String = "",
        tags: [String] = [],
        whereFroms: [String] = [],
        quarantineAgent: String? = nil,
        isScreenshot: Bool = false,
        isCloudOnly: Bool = false,
        isDirectory: Bool = false,
        isPackage: Bool = false,
        source: DownloadSource?? = nil,
        searchParent: String? = nil
    ) {
        self.path = path
        let resolvedName = name ?? (path as NSString).lastPathComponent
        self.name = resolvedName
        let e = (resolvedName as NSString).pathExtension.lowercased()
        self.ext = e
        self.kind = kind ?? KindClassifier.kind(forExtension: e, isDirectory: isDirectory, isPackage: isPackage)
        self.size = size
        self.created = created
        self.modified = modified
        self.added = added
        self.lastOpened = lastOpened
        self.rootID = rootID
        self.tags = tags
        self.whereFroms = whereFroms
        self.quarantineAgent = quarantineAgent
        self.isScreenshot = isScreenshot
        self.isCloudOnly = isCloudOnly
        if let explicit = source {
            self.source = explicit
        } else {
            self.source = SourceClassifier.classify(whereFroms: whereFroms, quarantineAgent: quarantineAgent)
        }
        self.searchName = FileItem.fold(resolvedName)
        self.searchParent = searchParent ?? FileItem.fold(FileItem.lastComponent(FileItem.parent(of: path)))
    }

    /// Everything given as stored; used when reading the saved index (nothing is recomputed).
    init(stored path: String, name: String, ext: String, kind: FileKind, size: Int64, created: Date, modified: Date,
         added: Date?, lastOpened: Date?, rootID: String, tags: [String], whereFroms: [String], quarantineAgent: String?,
         isScreenshot: Bool, isCloudOnly: Bool, source: DownloadSource?, searchName: String, searchParent: String) {
        self.path = path
        self.name = name
        self.ext = ext
        self.kind = kind
        self.size = size
        self.created = created
        self.modified = modified
        self.added = added
        self.lastOpened = lastOpened
        self.rootID = rootID
        self.tags = tags
        self.whereFroms = whereFroms
        self.quarantineAgent = quarantineAgent
        self.isScreenshot = isScreenshot
        self.isCloudOnly = isCloudOnly
        self.source = source
        self.searchName = searchName
        self.searchParent = searchParent
    }

    /// A file URL built without asking the disk whether the path is a folder (that check is slow in bulk).
    public var url: URL { URL(fileURLWithPath: path, isDirectory: kind == .folder || kind == .app) }
    public var parentPath: String { FileItem.parent(of: path) }
    public var parentName: String { FileItem.lastComponent(parentPath) }

    /// "/a/b/c.txt" → "/a/b" ("/" for top-level items).
    public static func parent(of path: String) -> String {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return "" }
        if slash == path.utf8.startIndex { return "/" }
        return String(path[..<slash])
    }

    /// "/a/b" → "b".
    public static func lastComponent(_ path: String) -> String {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return path }
        return String(path[path.utf8.index(after: slash)...])
    }
    public var baseName: String { (name as NSString).deletingPathExtension }
    public var isFolder: Bool { kind == .folder }

    /// The most recent of created / modified / added: "when did this last show up or change".
    public var activityDate: Date {
        var d = modified
        if created > d { d = created }
        if let a = added, a > d { d = a }
        return d
    }

    /// When the file arrived (download date for Downloads), falling back to creation.
    public var arrivalDate: Date { added ?? created }

    /// When the user last touched it: opened, else arrived.
    public var lastUsedDate: Date {
        if let o = lastOpened { return max(o, arrivalDate) }
        return arrivalDate
    }

    public var category: LibraryCategory? { kind.category }

    /// Lowercased and diacritic-insensitive form used for all matching.
    public static func fold(_ s: String) -> String {
        // Plain ASCII (most file names) only needs lowercasing, which is far cheaper than Unicode folding.
        var ascii = true
        var upper = false
        for b in s.utf8 {
            if b >= 0x80 { ascii = false; break }
            if b >= 65 && b <= 90 { upper = true }
        }
        if ascii {
            if !upper { return s }
            return String(decoding: s.utf8.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }, as: UTF8.self)
        }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Returns a copy with a different size (used when app bundle sizes are measured later).
    public func withSize(_ newSize: Int64) -> FileItem {
        var copy = self
        copy.size = newSize
        return copy
    }
}

extension FileItem {
    enum CodingKeys: String, CodingKey {
        case path, name, ext, kind, size, created, modified, added, lastOpened, rootID, tags, whereFroms, quarantineAgent
        case isScreenshot, isCloudOnly, source, searchName, searchParent
    }

    /// Reads items saved by any version (older ones had no `searchParent`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        ext = try c.decode(String.self, forKey: .ext)
        kind = try c.decode(FileKind.self, forKey: .kind)
        size = try c.decode(Int64.self, forKey: .size)
        created = try c.decode(Date.self, forKey: .created)
        modified = try c.decode(Date.self, forKey: .modified)
        added = try c.decodeIfPresent(Date.self, forKey: .added)
        lastOpened = try c.decodeIfPresent(Date.self, forKey: .lastOpened)
        rootID = try c.decode(String.self, forKey: .rootID)
        tags = try c.decode([String].self, forKey: .tags)
        whereFroms = try c.decode([String].self, forKey: .whereFroms)
        quarantineAgent = try c.decodeIfPresent(String.self, forKey: .quarantineAgent)
        isScreenshot = try c.decode(Bool.self, forKey: .isScreenshot)
        isCloudOnly = try c.decodeIfPresent(Bool.self, forKey: .isCloudOnly) ?? false
        source = try c.decodeIfPresent(DownloadSource.self, forKey: .source)
        searchName = try c.decodeIfPresent(String.self, forKey: .searchName) ?? FileItem.fold(name)
        searchParent = try c.decodeIfPresent(String.self, forKey: .searchParent)
            ?? FileItem.fold(FileItem.lastComponent(FileItem.parent(of: path)))
    }
}

public extension Array where Element == FileItem {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
}
