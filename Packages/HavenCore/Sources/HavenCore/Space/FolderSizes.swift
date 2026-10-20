import Foundation

/// Size and file count of every indexed folder (everything below it), worked out from the index in one pass:
/// files are added to their own folder, then each folder's total is added to the folders above it.
public struct FolderSizes: Sendable {
    public struct Entry: Hashable, Sendable {
        public var bytes: Int64 = 0
        /// Files below the folder (folders themselves aren't counted).
        public var files = 0
        public init(bytes: Int64 = 0, files: Int = 0) {
            self.bytes = bytes
            self.files = files
        }
    }

    public private(set) var entries: [String: Entry] = [:]
    /// Folders directly inside each folder (only folders that hold indexed files somewhere below).
    public private(set) var children: [String: [String]] = [:]
    /// Files directly inside each folder.
    public private(set) var direct: [String: Entry] = [:]

    public init() {}

    public subscript(path: String) -> Entry? { entries[path] }

    /// - Parameter tops: where adding up stops (the indexed folders); nothing above them gets a size.
    public static func compute(_ items: [FileItem], tops: [String]) -> FolderSizes {
        var sizes = FolderSizes()
        // 1. Files into their own folder.
        var direct: [String: Entry] = [:]
        for item in items where item.kind != .folder {
            let parent = FileItem.parent(of: item.path)
            direct[parent, default: Entry()].bytes += item.size
            direct[parent, default: Entry()].files += 1
        }
        // Folders with nothing inside still exist (with zero).
        for item in items where item.kind == .folder && direct[item.path] == nil {
            direct[item.path] = Entry()
        }
        sizes.direct = direct
        let topSet = Set(tops)

        // 2. Each folder's own files up through its parents (folders, not files: far fewer steps).
        var total: [String: Entry] = direct
        var children: [String: Set<String>] = [:]
        for (folder, entry) in direct {
            var current = folder
            while !topSet.contains(current) {
                let parent = FileItem.parent(of: current)
                guard !parent.isEmpty, parent != current else { break }
                children[parent, default: []].insert(current)
                if entry.bytes != 0 || entry.files != 0 {
                    total[parent, default: Entry()].bytes += entry.bytes
                    total[parent, default: Entry()].files += entry.files
                } else if total[parent] == nil {
                    total[parent] = Entry()
                }
                current = parent
            }
        }
        sizes.entries = total
        sizes.children = children.mapValues { Array($0) }
        return sizes
    }

    /// Subfolders of `path`, biggest first.
    public func subfolders(of path: String) -> [(path: String, entry: Entry)] {
        (children[path] ?? []).map { ($0, entries[$0] ?? Entry()) }
            .sorted { $0.entry.bytes != $1.entry.bytes ? $0.entry.bytes > $1.entry.bytes : $0.path < $1.path }
    }
}

/// Where the space goes: by kind, by source, by when files were last used, and the biggest files.
public struct SpaceReport: Sendable {
    public struct Slice: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let symbol: String
        public var bytes: Int64
        public var files: Int
    }

    public var totalBytes: Int64 = 0
    public var fileCount = 0
    public var byKind: [Slice] = []
    public var bySource: [Slice] = []
    public var byAge: [Slice] = []

    public init() {}

    /// Age buckets by when a file was last opened (or arrived, if never opened).
    public enum AgeBucket: String, CaseIterable, Sendable {
        case month, halfYear, year, twoYears, older

        public var title: String {
            switch self {
            case .month: return "Used in the last month"
            case .halfYear: return "1–6 months ago"
            case .year: return "6–12 months ago"
            case .twoYears: return "1–2 years ago"
            case .older: return "Over 2 years ago"
            }
        }

        public var symbol: String {
            switch self {
            case .month: return "clock"
            case .halfYear: return "calendar"
            case .year: return "calendar.badge.clock"
            case .twoYears: return "hourglass"
            case .older: return "archivebox"
            }
        }

        static func of(_ date: Date, now: Date) -> AgeBucket {
            let days = now.timeIntervalSince(date) / 86_400
            if days < 31 { return .month }
            if days < 183 { return .halfYear }
            if days < 365 { return .year }
            if days < 730 { return .twoYears }
            return .older
        }
    }

    public static func compute(_ items: [FileItem], now: Date = Date()) -> SpaceReport {
        var r = SpaceReport()
        var kinds: [FileKind: (Int64, Int)] = [:]
        var sources: [String: (DownloadSource, Int64, Int)] = [:]
        var ages: [AgeBucket: (Int64, Int)] = [:]
        for item in items where item.kind != .folder {
            r.totalBytes += item.size
            r.fileCount += 1
            kinds[item.kind, default: (0, 0)].0 += item.size
            kinds[item.kind, default: (0, 0)].1 += 1
            if let s = item.source {
                sources[s.id, default: (s, 0, 0)].1 += item.size
                sources[s.id, default: (s, 0, 0)].2 += 1
            }
            let bucket = AgeBucket.of(item.lastUsedDate, now: now)
            ages[bucket, default: (0, 0)].0 += item.size
            ages[bucket, default: (0, 0)].1 += 1
        }
        r.byKind = kinds.map { Slice(id: $0.key.rawValue, title: $0.key.pluralName, symbol: $0.key.symbolName, bytes: $0.value.0, files: $0.value.1) }
            .sorted { $0.bytes > $1.bytes }
        r.bySource = sources.values.map { Slice(id: $0.0.id, title: $0.0.name, symbol: $0.0.symbol, bytes: $0.1, files: $0.2) }
            .sorted { $0.bytes > $1.bytes }
        r.byAge = AgeBucket.allCases.map { b in
            Slice(id: b.rawValue, title: b.title, symbol: b.symbol, bytes: ages[b]?.0 ?? 0, files: ages[b]?.1 ?? 0)
        }
        return r
    }

    /// The biggest files at or below `folder` (all of them when nil), biggest first.
    public static func biggestFiles(_ items: [FileItem], under folder: String?, limit: Int = 30) -> [FileItem] {
        let prefix = folder.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var top: [FileItem] = []
        top.reserveCapacity(limit + 1)
        var floor: Int64 = -1
        for item in items where item.kind != .folder && item.size > floor {
            if let prefix, !item.path.hasPrefix(prefix) { continue }
            // Keep a small sorted list instead of sorting everything.
            let i = top.firstIndex { $0.size < item.size } ?? top.count
            top.insert(item, at: i)
            if top.count > limit {
                top.removeLast()
                floor = top.last?.size ?? -1
            }
        }
        return top
    }
}
