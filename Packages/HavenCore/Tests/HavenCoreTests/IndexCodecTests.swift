import Foundation
@testable import HavenCore
import XCTest

final class IndexCodecTests: XCTestCase {
    func testRoundTripLargeLibrary() throws {
        let items = SyntheticLibrary.make(count: 5_000, seed: 7)
        let data = IndexCodec.encode(items: items, rootPaths: ["/Users/me/Desktop", "/Users/me/Downloads"])
        let back = try IndexCodec.decode(data)
        XCTAssertEqual(back.rootPaths, ["/Users/me/Desktop", "/Users/me/Downloads"])
        XCTAssertEqual(back.items.count, items.count)
        XCTAssertEqual(back.items, items)
        XCTAssertEqual(back.items.map(\.searchParent), items.map(\.searchParent))
        XCTAssertEqual(back.items.map(\.source), items.map(\.source))
    }

    func testRoundTripEdgeCases() throws {
        let d = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456)
        let items = [
            FileItem(path: "/top-level.txt", created: d, modified: d),
            FileItem(path: "relative.txt", created: d, modified: d),
            FileItem(path: "/Users/me/Downloads/Ünïcödé Café 📸.HEIC", size: 1, created: d, modified: d, added: d,
                     lastOpened: d, rootID: "downloads", tags: ["Work", "Rot"], whereFroms: ["https://mail.google.com/x", ""],
                     quarantineAgent: "Google Chrome", isScreenshot: true, isCloudOnly: true),
            FileItem(path: "/Users/me/Shown Name.pdf", name: "Different Name.pdf", created: d, modified: d),
            FileItem(path: "/Applications/Some.app", size: 123_456_789, created: d, modified: d, rootID: "applications",
                     isPackage: true, source: .some(nil)),
            FileItem(path: "/Users/me/x/folder", created: d, modified: d, isDirectory: true),
            FileItem(path: "/Users/me/x/site.zip", created: d, modified: d, whereFroms: ["https://files.example.org/a.zip"]),
        ]
        let back = try IndexCodec.decode(IndexCodec.encode(items: items, rootPaths: []))
        XCTAssertEqual(back.items, items)
        XCTAssertEqual(back.items[3].name, "Different Name.pdf")
        XCTAssertEqual(back.items[3].path, "/Users/me/Shown Name.pdf")
        XCTAssertEqual(back.items[2].source?.id, "gmail")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try IndexCodec.decode(Data("{\"version\":3}".utf8)))
        var data = IndexCodec.encode(items: SyntheticLibrary.make(count: 50), rootPaths: ["/a"])
        data = data.prefix(data.count / 2)
        XCTAssertThrowsError(try IndexCodec.decode(data))
    }

    func testOldJSONWithoutParentNameStillLoads() throws {
        let item = FileItem(path: "/Users/me/Trips/Goa Beach.jpg", created: Date(), modified: Date())
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        json.removeValue(forKey: "searchParent")
        let back = try JSONDecoder().decode(FileItem.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(back.searchParent, "trips")
        XCTAssertEqual(back, item)
    }

    func testNaturalNameOrder() {
        let d = Date()
        let names = ["file10.txt", "File2.txt", "file1.txt", "Écran.png", "ecran 2.png", "a.txt", "file02b.txt"]
        let items = names.map { FileItem(path: "/x/" + $0, created: d, modified: d) }
        XCTAssertEqual(FileSortOrder.nameAZ.sorted(items).map(\.name),
                       ["a.txt", "ecran 2.png", "Écran.png", "file1.txt", "File2.txt", "file02b.txt", "file10.txt"])
        XCTAssertEqual(FileSortOrder.nameZA.sorted(items).map(\.name).first, "file10.txt")
    }

    func testBigSortsMatchASimpleSort() {
        // Large enough to be split across cores and merged.
        let items = SyntheticLibrary.make(count: 60_000, seed: 11)
        let keys = items.map { NaturalOrder.key($0.searchName) }
        func simple(_ less: (Int, Int) -> Bool) -> [String] {
            Array(items.indices).sorted(by: less).map { items[$0].path }
        }
        XCTAssertEqual(FileSortOrder.nameAZ.sorted(items).map(\.path), simple { a, b in
            let c = NaturalOrder.compare(keys[a], keys[b]); return c != 0 ? c < 0 : a < b
        })
        XCTAssertEqual(FileSortOrder.nameZA.sorted(items).map(\.path), simple { a, b in
            let c = NaturalOrder.compare(keys[a], keys[b]); return c != 0 ? c > 0 : a < b
        })
        XCTAssertEqual(FileSortOrder.kind.sorted(items).map(\.path), simple { a, b in
            let ka = items[a].kind.rawValue, kb = items[b].kind.rawValue
            if ka != kb { return ka < kb }
            let c = NaturalOrder.compare(keys[a], keys[b]); return c != 0 ? c < 0 : a < b
        })
        XCTAssertEqual(FileSortOrder.sizeLargest.sorted(items).map(\.path), simple { a, b in
            items[a].size != items[b].size ? items[a].size > items[b].size : a < b
        })
        XCTAssertEqual(FileSortOrder.dateOldest.sorted(items).map(\.path), simple { a, b in
            items[a].activityDate != items[b].activityDate ? items[a].activityDate < items[b].activityDate : a < b
        })
        let flat = NaturalKeys(items.map(\.searchName))
        flat.withComparator { cmp in
            for (i, j) in [(0, 1), (5, 59_999), (31_000, 2), (7, 7)] {
                XCTAssertEqual(cmp(i, j).signum(), NaturalOrder.compare(keys[i], keys[j]).signum())
            }
        }
        XCTAssertEqual(FileSortOrder.nameAZ.sorted([]), [])
    }

    func testParallelSearchMatchesSequential() {
        let items = SyntheticLibrary.make(count: 30_000, seed: 3)
        for q in ["invoice", "beach 12", "pdfs from last year", "largest zips", "café notes", "#work", "a"] {
            let query = QueryParser.parse(q).query
            let saved = SearchEngine.parallelThreshold
            SearchEngine.parallelThreshold = .max
            let sequential = SearchEngine.search(query, in: items).map(\.path)
            let sequentialTop = SearchEngine.search(query, in: items, limit: 25).map(\.path)
            SearchEngine.parallelThreshold = 1_000
            let parallel = SearchEngine.search(query, in: items).map(\.path)
            let parallelTop = SearchEngine.search(query, in: items, limit: 25).map(\.path)
            SearchEngine.parallelThreshold = saved
            XCTAssertEqual(parallel, sequential, q)
            XCTAssertEqual(parallelTop, Array(sequential.prefix(25)), q)
            XCTAssertEqual(sequentialTop, Array(sequential.prefix(25)), q)
        }
    }

    func testPrefixAndMatchHelpers() {
        XCTAssertTrue(TextMatch.starts(with: Array("rep".utf8), "report.pdf"))
        XCTAssertTrue(TextMatch.starts(with: [], "x"))
        XCTAssertFalse(TextMatch.starts(with: Array("report.pdfx".utf8), "report.pdf"))
        XCTAssertFalse(TextMatch.starts(with: Array("ep".utf8), "report.pdf"))
        XCTAssertEqual(TextMatch.score(Array("rep".utf8), in: "report"), 30)
        XCTAssertEqual(TextMatch.score(Array("port".utf8), in: "my port"), 20)
        XCTAssertEqual(TextMatch.score(Array("port".utf8), in: "report"), 12)
        XCTAssertEqual(TextMatch.score(Array("zz".utf8), in: "report"), 0)
    }

    func testCancelledSearchStopsEarly() {
        let items = SyntheticLibrary.make(count: 20_000, seed: 5)
        let query = QueryParser.parse("notes").query
        XCTAssertTrue(SearchEngine.search(query, in: items, isCancelled: { true }).isEmpty)
    }
}
