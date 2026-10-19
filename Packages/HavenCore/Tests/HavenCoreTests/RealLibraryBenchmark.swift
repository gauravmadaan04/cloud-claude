import Foundation
@testable import HavenCore
import XCTest

/// Speed check on your own folders. Read-only: it lists and reads file information, never writes, moves or
/// deletes anything. Runs only when asked:
///
///     HAVEN_BENCH_ROOT=~ swift test -c release --filter RealLibraryBenchmark
final class RealLibraryBenchmark: XCTestCase {
    func testScanSearchAndIndexYourFolders() throws {
        guard let raw = ProcessInfo.processInfo.environment["HAVEN_BENCH_ROOT"] else { return }
        let home = (raw as NSString).expandingTildeInPath
        let roots = IndexRoot.standard(home: home).filter { FileManager.default.fileExists(atPath: $0.path) }

        func time<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
            let t = Date()
            let r = try block()
            print(String(format: "BENCH %-46@ %9.1f ms", label as NSString, Date().timeIntervalSince(t) * 1000))
            return r
        }

        // Every folder on its own core, as the app does.
        let found = time("scan \(roots.map(\.name).joined(separator: ", "))") { () -> [FileItem] in
            var results = [[FileItem]](repeating: [], count: roots.count)
            results.withUnsafeMutableBufferPointer { out in
                DispatchQueue.concurrentPerform(iterations: roots.count) { i in
                    out[i] = FileScanner.scan(root: roots[i])
                }
            }
            return results.flatMap { $0 }
        }
        print("BENCH files found: \(found.count)")
        let items = time("sort newest first") { FileSortOrder.dateNewest.sorted(found) }

        let data = time("save index (in memory)") { IndexCodec.encode(items: items, rootPaths: roots.map(\.path)) }
        print("BENCH index size: \(data.count / 1024) KB")
        let back = try time("load index") { try IndexCodec.decode(data) }
        XCTAssertEqual(back.items.count, items.count)

        for q in ["pdf", "screenshots from last week", "invoice", "photos over 5 MB", "from whatsapp", "largest videos", "a"] {
            let query = QueryParser.parse(q).query
            let hits = time("search “\(q)”") { SearchEngine.search(query, in: items) }
            _ = time("search “\(q)”, first 40") { SearchEngine.search(query, in: items, limit: 40) }
            print("BENCH   \(hits.count) matches")
        }
        _ = time("sort by name") { FileSortOrder.nameAZ.sorted(items) }
        _ = time("sort by size") { FileSortOrder.sizeLargest.sorted(items) }

        // A live update: re-list Downloads and fold it into the index.
        let downloads = (home as NSString).appendingPathComponent("Downloads")
        let listing = time("list Downloads") { FileScanner.list(directory: downloads, rootID: "downloads") }
        _ = time("merge a changed folder") { IndexMerge.apply(base: items, listed: [downloads: listing]) }
        _ = time("forget 3 files") { IndexMerge.removing(Set(items.prefix(3).map(\.path)), from: items) }
    }
}
