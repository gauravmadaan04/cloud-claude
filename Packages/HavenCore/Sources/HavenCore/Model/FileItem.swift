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
        source: DownloadSource?? = nil
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
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var parentPath: String { (path as NSString).deletingLastPathComponent }
    public var parentName: String { (parentPath as NSString).lastPathComponent }
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
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Returns a copy with a different size (used when app bundle sizes are measured later).
    public func withSize(_ newSize: Int64) -> FileItem {
        var copy = self
        copy.size = newSize
        return copy
    }
}

public extension Array where Element == FileItem {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
}
