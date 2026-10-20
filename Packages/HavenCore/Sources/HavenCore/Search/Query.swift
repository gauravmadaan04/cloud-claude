import Foundation

public enum TimeUnit: String, Codable, Sendable, Hashable {
    case day, week, month, year

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    func label(_ n: Int) -> String {
        n == 1 ? rawValue : rawValue + "s"
    }
}

/// A date range described relatively, so saved searches like "last week" keep meaning "last week".
public indirect enum DateSpec: Codable, Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear
    /// Within the past N units ("past 3 months").
    case within(Int, TimeUnit)
    /// Older than N units ("older than 6 months").
    case olderThan(Int, TimeUnit)
    /// The calendar unit N units ago ("2 weeks ago").
    case ago(Int, TimeUnit)
    /// A month (1–12); nil year means its most recent occurrence.
    case month(Int, year: Int?)
    case year(Int)
    /// Most recent given weekday (1 = Sunday … 7 = Saturday), today included.
    case weekday(Int)
    case since(DateSpec)
    case before(DateSpec)
    case after(DateSpec)

    /// Half-open interval [start, end). Either side may be open.
    public func resolve(now: Date = Date(), calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        let cal = calendar
        func interval(_ c: Calendar.Component, _ d: Date) -> (Date?, Date?) {
            if let i = cal.dateInterval(of: c, for: d) { return (i.start, i.end) }
            return (nil, nil)
        }
        func add(_ unit: TimeUnit, _ n: Int, _ d: Date) -> Date {
            cal.date(byAdding: unit.component, value: n, to: d) ?? d
        }
        switch self {
        case .today:
            return interval(.day, now)
        case .yesterday:
            return interval(.day, add(.day, -1, now))
        case .thisWeek:
            return interval(.weekOfYear, now)
        case .lastWeek:
            return interval(.weekOfYear, add(.week, -1, now))
        case .thisMonth:
            return interval(.month, now)
        case .lastMonth:
            return interval(.month, add(.month, -1, now))
        case .thisYear:
            return interval(.year, now)
        case .lastYear:
            return interval(.year, add(.year, -1, now))
        case .within(let n, let unit):
            return (add(unit, -n, now), nil)
        case .olderThan(let n, let unit):
            return (nil, add(unit, -n, now))
        case .ago(let n, let unit):
            return interval(unit.component, add(unit, -n, now))
        case .month(let m, let y):
            let currentYear = cal.component(.year, from: now)
            let currentMonth = cal.component(.month, from: now)
            let year = y ?? (m <= currentMonth ? currentYear : currentYear - 1)
            guard let d = cal.date(from: DateComponents(year: year, month: m, day: 1)) else { return (nil, nil) }
            return interval(.month, d)
        case .year(let y):
            guard let d = cal.date(from: DateComponents(year: y, month: 1, day: 1)) else { return (nil, nil) }
            return interval(.year, d)
        case .weekday(let w):
            let today = cal.component(.weekday, from: now)
            let back = (today - w + 7) % 7
            return interval(.day, add(.day, -back, now))
        case .since(let inner):
            return (inner.resolve(now: now, calendar: cal).start, nil)
        case .before(let inner):
            return (nil, inner.resolve(now: now, calendar: cal).start)
        case .after(let inner):
            let r = inner.resolve(now: now, calendar: cal)
            return (r.end ?? r.start, nil)
        }
    }

    public var label: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .lastWeek: return "Last week"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .thisYear: return "This year"
        case .lastYear: return "Last year"
        case .within(let n, let u): return "Past \(n == 1 ? "" : "\(n) ")\(u.label(n))"
        case .olderThan(let n, let u): return "Older than \(n) \(u.label(n))"
        case .ago(let n, let u): return "\(n) \(u.label(n)) ago"
        case .month(let m, let y):
            let name = DateSpec.monthNames[max(0, min(11, m - 1))].capitalized
            return y.map { "\(name) \($0)" } ?? name
        case .year(let y): return String(y)
        case .weekday(let w): return DateSpec.weekdayNames[max(0, min(6, w - 1))].capitalized
        case .since(let inner): return "Since \(inner.label.lowercasedFirst)"
        case .before(let inner): return "Before \(inner.label.lowercasedFirst)"
        case .after(let inner): return "After \(inner.label.lowercasedFirst)"
        }
    }

    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august",
                             "september", "october", "november", "december"]
    static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
}

extension String {
    var lowercasedFirst: String {
        guard let f = first else { return self }
        // Keep month names and years capitalised.
        if DateSpec.monthNames.contains(lowercased().split(separator: " ").first.map(String.init) ?? "") { return self }
        if DateSpec.weekdayNames.contains(lowercased()) { return self }
        return f.lowercased() + dropFirst()
    }
}

/// Which date a date filter looks at.
public enum DateField: String, Codable, Sendable, Hashable {
    /// Most recent of created/modified/added.
    case activity
    case modified
    case created
    /// Arrival date (download date for downloads).
    case added
    case opened

    public var verb: String? {
        switch self {
        case .activity: return nil
        case .modified: return "Edited"
        case .created: return "Created"
        case .added: return "Downloaded"
        case .opened: return "Opened"
        }
    }
}

public enum SortHint: String, Codable, Sendable, Hashable {
    case largest, smallest, newest, oldest

    public var label: String {
        switch self {
        case .largest: return "Largest first"
        case .smallest: return "Smallest first"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }
}

/// The structured form of a plain-English search.
public struct SearchQuery: Codable, Hashable, Sendable {
    /// Folded words that must all match (name, tags, folder, or text inside the file).
    public var terms: [String] = []
    public var kinds: Set<FileKind> = []
    public var extensions: Set<String> = []
    public var screenshots = false
    public var screenRecordings = false
    public var date: DateSpec?
    public var dateField: DateField = .activity
    public var minSize: Int64?
    public var maxSize: Int64?
    public var sourceIDs: Set<String> = []
    public var rootIDs: Set<String> = []
    public var tags: Set<String> = []
    /// Only files that were downloaded (have a source, or live in Downloads).
    public var downloadedOnly = false
    public var sort: SortHint?

    public init() {}

    public var hasTypeFilter: Bool { !kinds.isEmpty || !extensions.isEmpty || screenshots || screenRecordings }

    public var isEmpty: Bool {
        terms.isEmpty && !hasTypeFilter && date == nil && minSize == nil && maxSize == nil && sourceIDs.isEmpty
            && rootIDs.isEmpty && tags.isEmpty && !downloadedOnly && sort == nil
    }
}

public enum ChipKind: String, Codable, Sendable, Hashable {
    case type, date, size, source, location, tag, text, sort, downloaded
}

/// One visible piece of "how Haven read your search".
public struct QueryChip: Identifiable, Hashable, Sendable {
    public let kind: ChipKind
    public let label: String
    public let symbol: String
    /// Indexes of the words in the original text that produced this chip.
    public let tokenIndexes: [Int]

    public var id: String { "\(kind.rawValue):\(label)" }

    public init(kind: ChipKind, label: String, symbol: String, tokenIndexes: [Int]) {
        self.kind = kind
        self.label = label
        self.symbol = symbol
        self.tokenIndexes = tokenIndexes
    }
}

public struct ParsedQuery: Hashable, Sendable {
    public let text: String
    public let query: SearchQuery
    public let chips: [QueryChip]
    /// The original words, as typed (quoted phrases kept together).
    public let tokens: [String]

    /// A short readable title for the results: "PDFs · Last week · From Gmail".
    public var headline: String {
        let parts = chips.filter { $0.kind != .sort }.map(\.label)
        return parts.isEmpty ? text : parts.joined(separator: " · ")
    }

    /// The search text with the words behind `chip` removed, so removing a chip edits the search.
    public func text(removing chip: QueryChip) -> String {
        let drop = Set(chip.tokenIndexes)
        return tokens.enumerated().filter { !drop.contains($0.offset) }.map(\.element).joined(separator: " ")
    }
}

public enum ByteSize {
    public static let kb: Int64 = 1_000
    public static let mb: Int64 = 1_000_000
    public static let gb: Int64 = 1_000_000_000
    public static let tb: Int64 = 1_000_000_000_000

    /// "5 MB", "1.5 GB" in Finder's decimal units.
    public static func format(_ bytes: Int64) -> String {
        if bytes < kb { return "\(bytes) bytes" }
        let (unit, name): (Int64, String) = bytes < mb ? (kb, "KB") : bytes < gb ? (mb, "MB") : bytes < tb ? (gb, "GB") : (tb, "TB")
        // Whole numbers from 100 up (and for exact values), one decimal below. Integer maths: exact and quick.
        if bytes >= 100 * unit || bytes % unit == 0 { return "\((bytes + unit / 2) / unit) \(name)" }
        let tenths = (bytes * 10 + unit / 2) / unit
        return "\(tenths / 10).\(tenths % 10) \(name)"
    }
}
