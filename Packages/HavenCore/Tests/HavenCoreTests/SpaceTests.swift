import Foundation
@testable import HavenCore
import XCTest

final class SpaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func file(_ path: String, _ size: Int64, daysAgo: Double = 1, opened: Double? = nil, source: DownloadSource?? = nil) -> FileItem {
        let d = now.addingTimeInterval(-daysAgo * 86_400)
        return FileItem(path: path, size: size, created: d, modified: d,
                        lastOpened: opened.map { now.addingTimeInterval(-$0 * 86_400) }, source: source)
    }

    func folder(_ path: String) -> FileItem {
        FileItem(path: path, created: now, modified: now, isDirectory: true)
    }

    func testFolderSizesAddUpThroughEveryLevel() {
        let items = [
            folder("/U/Docs"), folder("/U/Docs/Taxes"), folder("/U/Docs/Taxes/2025"), folder("/U/Docs/Empty"),
            file("/U/Docs/a.pdf", 100),
            file("/U/Docs/Taxes/b.pdf", 20),
            file("/U/Docs/Taxes/2025/c.pdf", 3),
            file("/U/Docs/Taxes/2025/d.pdf", 4),
            file("/U/Downloads/x.zip", 1000),
        ]
        let sizes = FolderSizes.compute(items, tops: ["/U/Docs", "/U/Downloads"])
        XCTAssertEqual(sizes["/U/Docs"], .init(bytes: 127, files: 4))
        XCTAssertEqual(sizes["/U/Docs/Taxes"], .init(bytes: 27, files: 3))
        XCTAssertEqual(sizes["/U/Docs/Taxes/2025"], .init(bytes: 7, files: 2))
        XCTAssertEqual(sizes["/U/Docs/Empty"], .init(bytes: 0, files: 0))
        XCTAssertEqual(sizes["/U/Downloads"], .init(bytes: 1000, files: 1))
        XCTAssertNil(sizes["/U"], "nothing above the indexed folders is added up")
        XCTAssertEqual(sizes.subfolders(of: "/U/Docs").map(\.path), ["/U/Docs/Taxes", "/U/Docs/Empty"])
        XCTAssertEqual(sizes.direct["/U/Docs"], .init(bytes: 100, files: 1))
    }

    func testReportGroupsByKindSourceAndAge() {
        let gmail = SourceClassifier.source(withID: "gmail")
        let items = [
            file("/U/a.jpg", 10, daysAgo: 3),
            file("/U/b.jpg", 20, daysAgo: 400),
            file("/U/c.pdf", 5, daysAgo: 900, source: .some(gmail)),
            file("/U/d.pdf", 7, daysAgo: 900, opened: 2, source: .some(gmail)),
            folder("/U/f"),
        ]
        let r = SpaceReport.compute(items, now: now)
        XCTAssertEqual(r.totalBytes, 42)
        XCTAssertEqual(r.fileCount, 4)
        XCTAssertEqual(r.byKind.map(\.id), ["image", "pdf"])
        XCTAssertEqual(r.byKind.first?.bytes, 30)
        XCTAssertEqual(r.bySource.map(\.title), ["Gmail"])
        XCTAssertEqual(r.bySource.first?.files, 2)
        let age = Dictionary(uniqueKeysWithValues: r.byAge.map { ($0.id, $0.bytes) })
        XCTAssertEqual(age["month"], 10 + 7, "opening a file makes it recent")
        XCTAssertEqual(age["twoYears"], 20)
        XCTAssertEqual(age["older"], 5)
    }

    func testBiggestFilesUnderAFolder() {
        let items = (0..<200).map { file("/U/\($0 % 2 == 0 ? "A" : "B")/f\($0).bin", Int64($0)) }
        let all = SpaceReport.biggestFiles(items, under: nil, limit: 5)
        XCTAssertEqual(all.map(\.size), [199, 198, 197, 196, 195])
        let a = SpaceReport.biggestFiles(items, under: "/U/A", limit: 3)
        XCTAssertEqual(a.map(\.size), [198, 196, 194])
        XCTAssertEqual(SpaceReport.biggestFiles(items, under: "/U/A/", limit: 3).map(\.size), [198, 196, 194], "a trailing slash is fine")
    }

    func testSizesForALargeLibraryAreQuick() {
        let items = SyntheticLibrary.make(count: 60_000)
        let start = Date()
        let sizes = FolderSizes.compute(items, tops: ["/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads",
                                                      "/Users/me/Pictures", "/Users/me/Movies", "/Users/me/Music"])
        let report = SpaceReport.compute(items)
        let elapsed = Date().timeIntervalSince(start)
        let tops = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map { "/Users/me/" + $0 }
        let summed = tops.reduce(Int64(0)) { $0 + (sizes[$1]?.bytes ?? 0) }
        XCTAssertEqual(summed, report.totalBytes, "every byte lands in exactly one indexed folder")
        XCTAssertLessThan(elapsed, 5)
    }
}
