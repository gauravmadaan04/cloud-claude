import Foundation

public enum SearchEngine {

    /// Text Haven has read from a file (OCR, PDF text…), already folded. Return nil when unknown.
    public typealias TextLookup = (String) -> String?

    public struct Hit: Sendable {
        public let item: FileItem
        public let score: Int
        /// True when a word only matched text inside the file (shown as "Found in text").
        public let matchedInText: Bool
    }

    public static func search(
        _ query: SearchQuery,
        in items: [FileItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        text: TextLookup? = nil,
        limit: Int? = nil
    ) -> [FileItem] {
        hits(query, in: items, now: now, calendar: calendar, text: text, limit: limit).map(\.item)
    }

    public static func hits(
        _ query: SearchQuery,
        in items: [FileItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        text: TextLookup? = nil,
        limit: Int? = nil
    ) -> [Hit] {
        let range = query.date?.resolve(now: now, calendar: calendar)
        let foldedTags = Set(query.tags.map(FileItem.fold))
        var hits: [Hit] = []
        hits.reserveCapacity(min(items.count, 4096))
        for item in items {
            if let hit = evaluate(item, query, range: range, foldedTags: foldedTags, text: text) {
                hits.append(hit)
            }
        }
        sort(&hits, query: query)
        if let limit, hits.count > limit { return Array(hits.prefix(limit)) }
        return hits
    }

    static func evaluate(_ item: FileItem, _ q: SearchQuery, range: (start: Date?, end: Date?)?, foldedTags: Set<String>, text: TextLookup?) -> Hit? {
        // Folders only show up when asked for, or when matching words by name.
        if item.kind == .folder {
            let wantsFolders = q.kinds.contains(.folder)
            let nameSearch = !q.hasTypeFilter && !q.terms.isEmpty && q.minSize == nil && q.maxSize == nil && q.sourceIDs.isEmpty
            if !(wantsFolders || nameSearch) { return nil }
        }
        if q.hasTypeFilter {
            let typeOK = q.kinds.contains(item.kind)
                || (!q.extensions.isEmpty && q.extensions.contains(item.ext))
                || (q.screenshots && item.isScreenshot && item.kind == .image)
                || (q.screenRecordings && item.isScreenshot && item.kind == .video)
            if !typeOK { return nil }
        }
        if let r = range {
            let date: Date?
            switch q.dateField {
            case .activity: date = item.activityDate
            case .modified: date = item.modified
            case .created: date = item.created
            case .added: date = item.arrivalDate
            case .opened: date = item.lastOpened
            }
            guard let d = date else { return nil }
            if let s = r.start, d < s { return nil }
            if let e = r.end, d >= e { return nil }
        }
        if let lo = q.minSize, item.size < lo { return nil }
        if let hi = q.maxSize, item.size > hi { return nil }
        if !q.sourceIDs.isEmpty {
            guard let s = item.source, q.sourceIDs.contains(s.id) else { return nil }
        }
        if q.downloadedOnly && item.source == nil && item.rootID != "downloads" { return nil }
        if !q.rootIDs.isEmpty && !q.rootIDs.contains(item.rootID) { return nil }
        if !foldedTags.isEmpty {
            let itemTags = Set(item.tags.map(FileItem.fold))
            if !foldedTags.isSubset(of: itemTags) { return nil }
        }

        var score = 0
        var onlyText = false
        if !q.terms.isEmpty {
            var folderName: String?
            var content: String??
            for term in q.terms {
                let s = termScore(term, in: item.searchName)
                if s > 0 { score += s; continue }
                if item.tags.contains(where: { FileItem.fold($0).contains(term) }) { score += 10; continue }
                if folderName == nil { folderName = FileItem.fold(item.parentName) }
                if folderName!.contains(term) { score += 5; continue }
                if content == nil { content = .some(text?(item.path)) }
                if let c = content!, c.contains(term) {
                    score += 4
                    onlyText = true
                    continue
                }
                return nil
            }
        }
        return Hit(item: item, score: score, matchedInText: onlyText)
    }

    /// How well a word matches a (folded) file name.
    static func termScore(_ term: String, in name: String) -> Int {
        guard let r = name.range(of: term) else { return 0 }
        if r.lowerBound == name.startIndex { return 30 }
        let before = name[name.index(before: r.lowerBound)]
        if !before.isLetter && !before.isNumber { return 20 }
        // camelCase or digit boundaries count as word starts too
        return 12
    }

    static func sort(_ hits: inout [Hit], query: SearchQuery) {
        switch query.sort {
        case .largest?: hits.sort { $0.item.size != $1.item.size ? $0.item.size > $1.item.size : $0.item.activityDate > $1.item.activityDate }
        case .smallest?: hits.sort { $0.item.size != $1.item.size ? $0.item.size < $1.item.size : $0.item.activityDate > $1.item.activityDate }
        case .oldest?: hits.sort { $0.item.activityDate < $1.item.activityDate }
        case .newest?: hits.sort { $0.item.activityDate > $1.item.activityDate }
        case nil:
            if query.terms.isEmpty {
                hits.sort { $0.item.activityDate > $1.item.activityDate }
            } else {
                hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.activityDate > $1.item.activityDate }
            }
        }
    }
}

/// How lists can be sorted in the browser.
public enum FileSortOrder: String, Codable, CaseIterable, Sendable, Identifiable {
    case dateNewest, dateOldest, nameAZ, nameZA, sizeLargest, sizeSmallest, kind

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dateNewest: return "Date (newest first)"
        case .dateOldest: return "Date (oldest first)"
        case .nameAZ: return "Name (A–Z)"
        case .nameZA: return "Name (Z–A)"
        case .sizeLargest: return "Size (largest first)"
        case .sizeSmallest: return "Size (smallest first)"
        case .kind: return "Kind"
        }
    }

    public func sorted(_ items: [FileItem]) -> [FileItem] {
        switch self {
        case .dateNewest: return items.sorted { $0.activityDate > $1.activityDate }
        case .dateOldest: return items.sorted { $0.activityDate < $1.activityDate }
        case .nameAZ: return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameZA: return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .sizeLargest: return items.sorted { $0.size > $1.size }
        case .sizeSmallest: return items.sorted { $0.size < $1.size }
        case .kind:
            return items.sorted {
                $0.kind.rawValue != $1.kind.rawValue ? $0.kind.rawValue < $1.kind.rawValue
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    public init(hint: SortHint) {
        switch hint {
        case .largest: self = .sizeLargest
        case .smallest: self = .sizeSmallest
        case .newest: self = .dateNewest
        case .oldest: self = .dateOldest
        }
    }
}
