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
        limit: Int? = nil,
        isCancelled: (() -> Bool)? = nil
    ) -> [FileItem] {
        matches(query, in: items, now: now, calendar: calendar, text: text, limit: limit, isCancelled: isCancelled)
            .map { items[Int($0.index)] }
    }

    /// Libraries bigger than this are searched on all cores.
    static var parallelThreshold = 16_384

    public static func hits(
        _ query: SearchQuery,
        in items: [FileItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        text: TextLookup? = nil,
        limit: Int? = nil,
        isCancelled: (() -> Bool)? = nil
    ) -> [Hit] {
        matches(query, in: items, now: now, calendar: calendar, text: text, limit: limit, isCancelled: isCancelled)
            .map { Hit(item: items[Int($0.index)], score: Int($0.score), matchedInText: $0.inText) }
    }

    /// Matching files as small records, best first.
    static func matches(
        _ query: SearchQuery,
        in items: [FileItem],
        now: Date,
        calendar: Calendar,
        text: TextLookup?,
        limit: Int?,
        isCancelled: (() -> Bool)?
    ) -> [Found] {
        let plan = Plan(query, now: now, calendar: calendar)
        let n = items.count
        var found: [Found]
        if n >= parallelThreshold {
            let chunks = min(256, max(2, n / 4096))
            let size = (n + chunks - 1) / chunks
            var parts = [[Found]](repeating: [], count: chunks)
            parts.withUnsafeMutableBufferPointer { out in
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    let lo = c * size
                    let hi = min(n, lo + size)
                    guard lo < hi else { return }
                    out[c] = scan(items, lo..<hi, plan, text, isCancelled)
                }
            }
            found = []
            found.reserveCapacity(parts.reduce(0) { $0 + $1.count })
            for p in parts { found.append(contentsOf: p) }
        } else {
            found = scan(items, 0..<n, plan, text, isCancelled)
        }
        if isCancelled?() == true { return [] }
        if let limit, found.count > limit {
            return topK(found, limit, plan.order.less)
        }
        plan.order.sort(&found)
        return found
    }

    /// What one matching file contributes while searching: small, so sorting is cheap.
    struct Found {
        var index: Int32
        var score: Int32
        var inText: Bool
        var date: Double
        var size: Int64
    }

    /// The query with everything that doesn't depend on the file worked out once.
    struct Plan {
        let q: SearchQuery
        let range: (start: Date?, end: Date?)?
        let foldedTags: Set<String>
        let terms: [[UInt8]]
        let wantsFolders: Bool
        let nameSearch: Bool
        let order: Order

        init(_ q: SearchQuery, now: Date, calendar: Calendar) {
            self.q = q
            range = q.date?.resolve(now: now, calendar: calendar)
            foldedTags = Set(q.tags.map(FileItem.fold))
            terms = q.terms.map { Array($0.utf8) }
            wantsFolders = q.kinds.contains(.folder)
            nameSearch = !q.hasTypeFilter && !q.terms.isEmpty && q.minSize == nil && q.maxSize == nil && q.sourceIDs.isEmpty
            switch q.sort {
            case .largest?: order = .sizeDesc
            case .smallest?: order = .sizeAsc
            case .oldest?: order = .dateAsc
            case .newest?: order = .dateDesc
            case nil: order = q.terms.isEmpty ? .dateDesc : .score
            }
        }
    }

    /// Result order; ties keep the library's order (newest activity first).
    enum Order {
        case score, dateDesc, dateAsc, sizeDesc, sizeAsc

        var less: (Found, Found) -> Bool {
            switch self {
            case .score: return Order.byScore
            case .dateDesc: return Order.byDateDesc
            case .dateAsc: return Order.byDateAsc
            case .sizeDesc: return Order.bySizeDesc
            case .sizeAsc: return Order.bySizeAsc
            }
        }

        func sort(_ found: inout [Found]) {
            // Written out per case so the compiler can inline each comparison.
            switch self {
            case .score: found.sort(by: Order.byScore)
            case .dateDesc: found.sort(by: Order.byDateDesc)
            case .dateAsc: found.sort(by: Order.byDateAsc)
            case .sizeDesc: found.sort(by: Order.bySizeDesc)
            case .sizeAsc: found.sort(by: Order.bySizeAsc)
            }
        }

        @inline(__always) static func byDateDesc(_ a: Found, _ b: Found) -> Bool {
            a.date != b.date ? a.date > b.date : a.index < b.index
        }
        @inline(__always) static func byDateAsc(_ a: Found, _ b: Found) -> Bool {
            a.date != b.date ? a.date < b.date : a.index < b.index
        }
        @inline(__always) static func byScore(_ a: Found, _ b: Found) -> Bool {
            a.score != b.score ? a.score > b.score : byDateDesc(a, b)
        }
        @inline(__always) static func bySizeDesc(_ a: Found, _ b: Found) -> Bool {
            a.size != b.size ? a.size > b.size : byDateDesc(a, b)
        }
        @inline(__always) static func bySizeAsc(_ a: Found, _ b: Found) -> Bool {
            a.size != b.size ? a.size < b.size : byDateDesc(a, b)
        }
    }

    static func scan(_ items: [FileItem], _ range: Range<Int>, _ plan: Plan, _ text: TextLookup?, _ isCancelled: (() -> Bool)?) -> [Found] {
        var out: [Found] = []
        var i = range.lowerBound
        while i < range.upperBound {
            if i & 4095 == 0, let isCancelled, isCancelled() { return [] }
            let item = items[i]
            if let (score, inText) = evaluate(item, plan, text) {
                out.append(Found(index: Int32(i), score: Int32(score), inText: inText,
                                 date: item.activityDate.timeIntervalSinceReferenceDate, size: item.size))
            }
            i += 1
        }
        return out
    }

    /// The best `k` in order, without sorting everything.
    static func topK(_ all: [Found], _ k: Int, _ less: (Found, Found) -> Bool) -> [Found] {
        guard k > 0 else { return [] }
        var best: [Found] = []
        best.reserveCapacity(k + 1)
        for f in all {
            if best.count == k, !less(f, best[k - 1]) { continue }
            var lo = 0, hi = best.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if less(f, best[mid]) { hi = mid } else { lo = mid + 1 }
            }
            best.insert(f, at: lo)
            if best.count > k { best.removeLast() }
        }
        return best
    }

    static func evaluate(_ item: FileItem, _ p: Plan, _ text: TextLookup?) -> (Int, Bool)? {
        let q = p.q
        // Folders only show up when asked for, or when matching words by name.
        if item.kind == .folder && !(p.wantsFolders || p.nameSearch) { return nil }
        if q.hasTypeFilter {
            let typeOK = q.kinds.contains(item.kind)
                || (!q.extensions.isEmpty && q.extensions.contains(item.ext))
                || (q.screenshots && item.isScreenshot && item.kind == .image)
                || (q.screenRecordings && item.isScreenshot && item.kind == .video)
            if !typeOK { return nil }
        }
        if let r = p.range {
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
        if !p.foldedTags.isEmpty {
            let itemTags = Set(item.tags.map(FileItem.fold))
            if !p.foldedTags.isSubset(of: itemTags) { return nil }
        }

        var score = 0
        var onlyText = false
        if !p.terms.isEmpty {
            var content: String??
            for term in p.terms {
                let s = TextMatch.score(term, in: item.searchName)
                if s > 0 { score += s; continue }
                if !item.tags.isEmpty, item.tags.contains(where: { TextMatch.contains(term, in: FileItem.fold($0)) }) {
                    score += 10
                    continue
                }
                if TextMatch.contains(term, in: item.searchParent) { score += 5; continue }
                // Only kinds Haven reads text from (or transcribed) can match inside the file.
                guard item.kind.hasSearchableText, let text else { return nil }
                if content == nil { content = .some(text(item.path)) }
                if let c = content!, TextMatch.contains(term, in: c) || TextMatch.containsIgnoringHyphens(term, in: c) {
                    score += 4
                    onlyText = true
                    continue
                }
                return nil
            }
        }
        return (score, onlyText)
    }

    /// How well a word matches a (folded) file name.
    static func termScore(_ term: String, in name: String) -> Int {
        TextMatch.score(Array(term.utf8), in: name)
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
        case .dateNewest: return Self.ordered(items, items.map { $0.activityDate.timeIntervalSinceReferenceDate }, descending: true)
        case .dateOldest: return Self.ordered(items, items.map { $0.activityDate.timeIntervalSinceReferenceDate }, descending: false)
        case .sizeLargest: return Self.ordered(items, items.map(\.size), descending: true)
        case .sizeSmallest: return Self.ordered(items, items.map(\.size), descending: false)
        case .nameAZ, .nameZA:
            let keys = NaturalKeys(items.map(\.searchName))
            let desc = self == .nameZA
            let order = keys.withComparator { cmp in
                Self.sortedOrder(items.count) { a, b in
                    let c = cmp(a, b)
                    if c != 0 { return desc ? c > 0 : c < 0 }
                    return a < b
                }
            }
            return order.map { items[$0] }
        case .kind:
            let keys = NaturalKeys(items.map(\.searchName))
            let kinds = items.map { Self.kindRank[$0.kind] ?? 0 }
            let order = kinds.withUnsafeBufferPointer { k in
                keys.withComparator { cmp in
                    Self.sortedOrder(items.count) { a, b in
                        if k[a] != k[b] { return k[a] < k[b] }
                        let c = cmp(a, b)
                        return c != 0 ? c < 0 : a < b
                    }
                }
            }
            return order.map { items[$0] }
        }
    }

    /// Kinds in alphabetical order of their names.
    static let kindRank: [FileKind: Int] = Dictionary(uniqueKeysWithValues:
        FileKind.allCases.sorted { $0.rawValue < $1.rawValue }.enumerated().map { ($1, $0) })

    /// Sorts by a precomputed key (cheap to compare), keeping the incoming order for ties.
    public static func ordered<K: Comparable>(_ items: [FileItem], _ keys: [K], descending: Bool) -> [FileItem] {
        let order = keys.withUnsafeBufferPointer { k in
            sortedOrder(items.count) { a, b in
                if k[a] != k[b] { return descending ? k[a] > k[b] : k[a] < k[b] }
                return a < b
            }
        }
        return order.map { items[$0] }
    }

    /// The positions 0..<count in `less` order. Big lists are sorted in slices on every core, then merged.
    /// `less` must be a strict total order (break ties by position) and safe to call from several threads.
    static func sortedOrder(_ count: Int, by less: (Int, Int) -> Bool) -> [Int] {
        var order = Array(0..<count)
        let parts = count >= 40_000 ? min(max(1, ProcessInfo.processInfo.activeProcessorCount), 16) : 1
        guard parts > 1 else {
            order.sort(by: less)
            return order
        }
        let size = (count + parts - 1) / parts
        order.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: parts) { p in
                let lo = p * size, hi = min(count, lo + size)
                guard lo < hi else { return }
                var slice = UnsafeMutableBufferPointer(rebasing: buf[lo..<hi])
                slice.sort(by: less)
            }
        }
        var runs = stride(from: 0, to: count, by: size).map { $0..<min(count, $0 + size) }
        var other = [Int](repeating: 0, count: count)
        while runs.count > 1 {
            let pairs = (runs.count + 1) / 2
            let current = runs
            order.withUnsafeBufferPointer { src in
                other.withUnsafeMutableBufferPointer { dst in
                    DispatchQueue.concurrentPerform(iterations: pairs) { k in
                        let a = current[2 * k]
                        guard 2 * k + 1 < current.count else {
                            for i in a { dst[i] = src[i] }
                            return
                        }
                        let b = current[2 * k + 1]
                        var i = a.lowerBound, j = b.lowerBound, o = a.lowerBound
                        while i < a.upperBound && j < b.upperBound {
                            if less(src[j], src[i]) { dst[o] = src[j]; j += 1 } else { dst[o] = src[i]; i += 1 }
                            o += 1
                        }
                        while i < a.upperBound { dst[o] = src[i]; i += 1; o += 1 }
                        while j < b.upperBound { dst[o] = src[j]; j += 1; o += 1 }
                    }
                }
            }
            swap(&order, &other)
            runs = (0..<pairs).map { k in
                2 * k + 1 < current.count ? current[2 * k].lowerBound..<current[2 * k + 1].upperBound : current[2 * k]
            }
        }
        return order
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
