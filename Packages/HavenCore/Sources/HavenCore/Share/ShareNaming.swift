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
        case .table: return rows(items, dateFormatter).map { $0.map(tsvCell).joined(separator: "\t") }.joined(separator: "\n")
        case .csv: return rows(items, dateFormatter).map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        }
    }

    static func rows(_ items: [FileItem], _ formatter: DateFormatter?) -> [[String]] {
        let f = formatter ?? {
            let d = DateFormatter()
            d.locale = Locale(identifier: "en_US_POSIX")
            d.dateFormat = "yyyy-MM-dd HH:mm"
            return d
        }()
        var out = [columns]
        out.reserveCapacity(items.count + 1)
        for item in items {
            out.append([
                item.name, item.kind.displayName, item.kind == .folder ? "" : ByteSize.format(item.size),
                item.kind == .folder ? "" : String(item.size), f.string(from: item.activityDate), item.source?.name ?? "",
                item.parentName, item.path,
            ])
        }
        return out
    }

    static func tsvCell(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    static func csvCell(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) || s.hasPrefix(" ") || s.hasSuffix(" ") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
