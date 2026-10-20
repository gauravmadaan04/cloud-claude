import Foundation

/// Names for the copies "Make Shareable" writes next to the originals (which are never changed).
public enum ShareNaming {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case jpeg, smallerImage, smallerPDF, zip
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .jpeg: return "Save as JPEG"
            case .smallerImage: return "Make a Smaller Image"
            case .smallerPDF: return "Make a Smaller PDF"
            case .zip: return "Compress as ZIP"
            }
        }

        public var symbol: String {
            switch self {
            case .jpeg: return "photo"
            case .smallerImage: return "arrow.down.right.and.arrow.up.left"
            case .smallerPDF: return "doc.zipper"
            case .zip: return "archivebox"
            }
        }
    }

    /// Image types Haven can read and write as JPEG.
    public static let convertibleImages: Set<String> = ["heic", "heif", "png", "tiff", "tif", "webp", "bmp", "gif", "jpg", "jpeg", "jfif", "avif"]

    /// Whether an action makes sense for these files.
    public static func applies(_ kind: Kind, to items: [FileItem]) -> Bool {
        guard !items.isEmpty else { return false }
        switch kind {
        case .jpeg: return items.allSatisfy { $0.kind == .image && convertibleImages.contains($0.ext) && $0.ext != "jpg" && $0.ext != "jpeg" }
        case .smallerImage: return items.allSatisfy { $0.kind == .image && convertibleImages.contains($0.ext) }
        case .smallerPDF: return items.allSatisfy { $0.kind == .pdf }
        case .zip: return true
        }
    }

    /// The name of the copy (before making it unique in its folder).
    public static func outputName(for item: FileItem, kind: Kind) -> String {
        let base = RenamePlanner.split(item).base
        switch kind {
        case .jpeg: return base + ".jpg"
        case .smallerImage: return base + " (small).jpg"
        case .smallerPDF: return base + " (smaller).pdf"
        case .zip: return item.name + ".zip"
        }
    }

    /// "photo.zip" for one item, "Archive.zip" for several (like Finder).
    public static func zipName(for items: [FileItem]) -> String {
        items.count == 1 ? items[0].name + ".zip" : "Archive.zip"
    }

    /// The pixel size an image is scaled to for "smaller" (the long side), never enlarging.
    public static func smallerSide(width: Int, height: Int, target: Int = 2048) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > target, longest > 0 else { return (width, height) }
        let scale = Double(target) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}

/// A list of files as text for a spreadsheet or a message: names, paths, or a table.
public enum ListExport {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case names, paths, table, csv
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .names: return "Copy Names"
            case .paths: return "Copy Paths"
            case .table: return "Copy as Table"
            case .csv: return "Export as CSV…"
            }
        }
    }

    public static let columns = ["Name", "Kind", "Size", "Bytes", "Date", "Downloaded From", "Folder", "Path"]

    public static func text(_ items: [FileItem], format: Format, dateFormatter: DateFormatter? = nil) -> String {
        switch format {
        case .names: return items.map(\.name).joined(separator: "\n")
        case .paths: return items.map(\.path).joined(separator: "\n")
        case .table, .csv: return table(items, csv: format == .csv, dateFormatter: dateFormatter)
        }
    }

    /// Rows are written straight into text, a slice of the list per core (a 300,000-file list in well under a second).
    static func table(_ items: [FileItem], csv: Bool, dateFormatter: DateFormatter?) -> String {
        let sep = csv ? "," : "\t"
        let eol = csv ? "\r\n" : "\n"
        let cell: (String) -> String = csv ? csvCell : tsvCell
        let stamp = DateStamp(covering: items)
        let date: (Date) -> String = dateFormatter.map { f in { f.string(from: $0) } } ?? stamp.string
        func rows(_ range: Range<Int>) -> String {
            var out = ""
            out.reserveCapacity(range.count * 160)
            for i in range {
                let item = items[i]
                let isFolder = item.kind == .folder
                out += eol
                out += cell(item.name); out += sep
                out += item.kind.displayName; out += sep
                if !isFolder { out += ByteSize.format(item.size) }
                out += sep
                if !isFolder { out += String(item.size) }
                out += sep
                out += date(item.activityDate); out += sep
                out += cell(item.source?.name ?? ""); out += sep
                out += cell(item.parentName); out += sep
                out += cell(item.path)
            }
            return out
        }
        let n = items.count
        // A custom DateFormatter is used from one thread only.
        let chunks = dateFormatter == nil && n >= 4_000 ? min(ProcessInfo.processInfo.activeProcessorCount, 16) : 1
        let size = (n + chunks - 1) / max(1, chunks)
        var parts = [String](repeating: "", count: chunks)
        if chunks == 1 {
            parts[0] = rows(0..<n)
        } else {
            parts.withUnsafeMutableBufferPointer { out in
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    let lo = c * size, hi = min(n, lo + size)
                    if lo < hi { out[c] = rows(lo..<hi) }
                }
            }
        }
        return columns.joined(separator: sep) + parts.joined() + (csv ? eol : "")
    }

    static func tsvCell(_ s: String) -> String {
        // Almost no name has a tab or line break: check the bytes before building a new string.
        guard s.utf8.contains(where: { $0 == 9 || $0 == 10 || $0 == 13 }) else { return s }
        return String(decoding: s.utf8.map { $0 == 9 || $0 == 10 || $0 == 13 ? UInt8(ascii: " ") : $0 }, as: UTF8.self)
    }

    static func csvCell(_ s: String) -> String {
        let u = s.utf8
        guard u.contains(where: { $0 == 44 || $0 == 34 || $0 == 10 || $0 == 13 }) || u.first == 32 || u.last == 32 else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// "2026-10-12 14:05" in the Mac's time zone, by arithmetic instead of DateFormatter (which is slow for long lists).
/// The time zone's changes (summer time) over the dates in the list are looked up once.
struct DateStamp: Sendable {
    /// Where each stretch with one UTC offset begins (seconds since 1970, rising), and its offset.
    private var starts: [Double] = [-.infinity]
    private var offsets: [Int] = []

    init(covering items: [FileItem], zone: TimeZone = .current) {
        var lo = Double.infinity, hi = -Double.infinity
        for item in items {
            let t = item.activityDate.timeIntervalSince1970
            if t < lo { lo = t }
            if t > hi { hi = t }
        }
        self.init(from: lo, to: hi, zone: zone)
    }

    init(from lo: Double, to hi: Double, zone: TimeZone = .current) {
        // Only 1900–2200 is looked up (dates outside that use the nearest offset).
        let first = Date(timeIntervalSince1970: min(max(lo.isFinite ? lo : 0, -2_208_988_800), 7_258_118_400))
        let last = min(max(hi.isFinite ? hi : 0, -2_208_988_800), 7_258_118_400)
        offsets = [zone.secondsFromGMT(for: first)]
        var t = first
        for _ in 0..<2_000 {
            guard let next = zone.nextDaylightSavingTimeTransition(after: t), next.timeIntervalSince1970 <= last else { break }
            starts.append(next.timeIntervalSince1970)
            offsets.append(zone.secondsFromGMT(for: next))
            t = next
        }
    }

    func offset(at t: Double) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return offsets[lo]
    }

    func string(_ date: Date) -> String {
        let t = date.timeIntervalSince1970
        guard t.isFinite, abs(t) < 1e13 else { return "" }
        let local = Int64(t.rounded(.down)) + Int64(offset(at: t))
        let days = local >= 0 ? local / 86_400 : (local - 86_399) / 86_400
        let secs = local - days * 86_400
        // Days since 1970 → year, month, day (Howard Hinnant's civil_from_days).
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        guard (0...9_999).contains(year) else { return "" }
        var bytes: [UInt8] = Array("0000-00-00 00:00".utf8)
        func put(_ value: Int64, at end: Int) {
            var x = value
            var i = end
            while x > 0 {
                bytes[i] = UInt8(48 + x % 10)
                x /= 10
                i -= 1
            }
        }
        put(year, at: 3); put(month, at: 6); put(day, at: 9)
        put(secs / 3_600, at: 12); put(secs % 3_600 / 60, at: 15)
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Folders you used lately, for Quick Search and the Open/Save jump: the folders your newest files are in.
public enum RecentFolders {
    /// - Parameters:
    ///   - items: the index, newest activity first.
    ///   - skip: folders not worth listing (the home folder itself…).
    public static func list(_ items: [FileItem], limit: Int = 6, scanning: Int = 400, skip: Set<String> = []) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items.prefix(scanning) where item.kind != .folder {
            let dir = item.parentPath
            guard !skip.contains(dir), seen.insert(dir).inserted else { continue }
            out.append(dir)
            if out.count == limit { break }
        }
        return out
    }
}
