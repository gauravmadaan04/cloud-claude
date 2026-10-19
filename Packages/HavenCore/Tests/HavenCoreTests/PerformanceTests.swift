import Foundation
@testable import HavenCore
import XCTest

/// A realistic large library for speed checks. Timings print only with HAVEN_BENCH=1; the checks always run
/// on a smaller library so the suite stays quick.
enum SyntheticLibrary {
    static func make(count: Int, seed: UInt64 = 42) -> [FileItem] {
        var rng = SplitMix(seed: seed)
        let words = ["report", "invoice", "holiday", "beach", "project", "notes", "budget", "meeting", "résumé", "photo",
                     "draft", "final", "scan", "receipt", "contract", "design", "logo", "plan", "summary", "Goa", "Café",
                     "family", "trip", "screenshot", "export", "backup", "tax", "client", "slides", "data"]
        let exts = ["jpg", "png", "heic", "pdf", "docx", "xlsx", "pptx", "txt", "md", "swift", "zip", "dmg", "pkg",
                    "mp4", "mov", "mp3", "wav", "psd", "key", "csv"]
        let roots = ["desktop", "documents", "downloads", "pictures", "movies", "music"]
        let sites = ["https://mail.google.com/mail/u/0/", "https://chatgpt.com/c/1", "https://www.canva.com/design/x",
                     "https://github.com/a/b/archive/main.zip", "https://example.com/file", "https://web.whatsapp.com/"]
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // Folder tree: ~1 folder per 60 files.
        var folders: [(root: String, path: String)] = []
        for r in roots {
            let base = "/Users/me/" + r.capitalized
            folders.append((r, base))
            for i in 0..<(count / 60 / roots.count + 1) {
                let depth = Int(rng.next() % 4)
                var p = base
                for d in 0...depth { p += "/" + words[Int(rng.next() % UInt64(words.count))] + (d == depth ? " \(i)" : "") }
                folders.append((r, p))
            }
        }
        var items: [FileItem] = []
        items.reserveCapacity(count)
        for i in 0..<count {
            let folder = folders[Int(rng.next() % UInt64(folders.count))]
            let ext = exts[Int(rng.next() % UInt64(exts.count))]
            let w1 = words[Int(rng.next() % UInt64(words.count))]
            let w2 = words[Int(rng.next() % UInt64(words.count))]
            let name = "\(w1) \(w2) \(i % 997).\(ext)"
            let age = Double(rng.next() % (5 * 365 * 86_400))
            let created = now.addingTimeInterval(-age)
            let modified = created.addingTimeInterval(Double(rng.next() % 86_400))
            let fromWeb = folder.root == "downloads" && rng.next() % 3 != 0
            let whereFroms = fromWeb ? [sites[Int(rng.next() % UInt64(sites.count))]] : []
            let tags = rng.next() % 50 == 0 ? ["Work"] : []
            items.append(FileItem(
                path: folder.path + "/" + name, size: Int64(rng.next() % 50_000_000), created: created, modified: modified,
                added: folder.root == "downloads" ? modified : nil,
                lastOpened: rng.next() % 4 == 0 ? modified.addingTimeInterval(3600) : nil,
                rootID: folder.root, tags: tags, whereFroms: whereFroms,
                quarantineAgent: fromWeb ? "Safari" : nil,
                isScreenshot: name.hasPrefix("screenshot") && (ext == "png" || ext == "jpg")
            ))
        }
        return items
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

final class PerformanceTests: XCTestCase {
    static let bench = ProcessInfo.processInfo.environment["HAVEN_BENCH"] == "1"
    static var size: Int { bench ? 300_000 : 20_000 }

    func time<T>(_ label: String, repeat times: Int = 1, _ block: () throws -> T) rethrows -> T {
        var result: T?
        var best = Double.infinity
        for _ in 0..<times {
            let t = Date()
            result = try block()
            best = min(best, Date().timeIntervalSince(t))
        }
        if Self.bench { print(String(format: "BENCH %-44@ %8.1f ms", label as NSString, best * 1000)) }
        return result!
    }

    func testSearchSortAndIndexSpeed() throws {
        let items = time("make \(Self.size) items") { SyntheticLibrary.make(count: Self.size) }
        let queries = ["invoice", "pdfs from last week", "photos over 5 MB", "beach 12", "zip from github", "notes",
                       "largest videos", "#work", "café", "a"]
        for q in queries {
            let parsed = QueryParser.parse(q)
            _ = time("search “\(q)”", repeat: 3) { SearchEngine.search(parsed.query, in: items) }
            _ = time("search “\(q)” top 40", repeat: 3) { SearchEngine.search(parsed.query, in: items, limit: 40) }
        }
        for order in FileSortOrder.allCases {
            _ = time("sort \(order.rawValue)") { order.sorted(items) }
        }
        let sorted = FileSortOrder.dateNewest.sorted(items)
        let dir = sorted[100].parentPath
        let listing = sorted.filter { $0.parentPath == dir }
        let merged = time("live update: merge one folder", repeat: 3) { IndexMerge.apply(base: sorted, listed: [dir: listing]) }
        XCTAssertEqual(merged.count, sorted.count)
        _ = time("forget 3 files", repeat: 3) { IndexMerge.removing(Set(sorted.prefix(3).map(\.path)), from: sorted) }
        // The old JSON format, for comparison (slow; only with HAVEN_BENCH_JSON=1).
        if !Self.bench || ProcessInfo.processInfo.environment["HAVEN_BENCH_JSON"] != nil {
            let data = try time("JSON encode") { try JSONEncoder().encode(IndexSnapshot(rootPaths: ["/Users/me"], items: items)) }
            if Self.bench { print("BENCH JSON size \(data.count / 1024) KB") }
            let back = try time("JSON decode") { try JSONDecoder().decode(IndexSnapshot.self, from: data) }
            XCTAssertEqual(back.items.count, items.count)
        }
        let bin = time("binary encode", repeat: 2) { IndexCodec.encode(items: items, rootPaths: ["/Users/me"]) }
        if Self.bench { print("BENCH binary size \(bin.count / 1024) KB") }
        let decoded = try time("binary decode", repeat: 2) { try IndexCodec.decode(bin) }
        XCTAssertEqual(decoded.items.count, items.count)
    }
}
