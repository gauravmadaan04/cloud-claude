import Foundation
@testable import HavenCore
import XCTest

final class ShareAndExportTests: XCTestCase {
    let d = Date(timeIntervalSince1970: 1_760_270_400)

    func item(_ path: String, size: Int64 = 1_500_000, folder: Bool = false, froms: [String] = []) -> FileItem {
        FileItem(path: path, size: size, created: d, modified: d, whereFroms: froms, isDirectory: folder)
    }

    func testCopyNamesAndWhichActionsApply() {
        let heic = item("/p/IMG_2041.HEIC"), jpg = item("/p/beach.jpg"), pdf = item("/p/report.v2.pdf"), folder = item("/p/Trip", folder: true)
        XCTAssertEqual(ShareNaming.outputName(for: heic, kind: .jpeg), "IMG_2041.jpg")
        XCTAssertEqual(ShareNaming.outputName(for: jpg, kind: .smallerImage), "beach (small).jpg")
        XCTAssertEqual(ShareNaming.outputName(for: pdf, kind: .smallerPDF), "report.v2 (smaller).pdf")
        XCTAssertEqual(ShareNaming.zipName(for: [folder]), "Trip.zip")
        XCTAssertEqual(ShareNaming.zipName(for: [heic, pdf]), "Archive.zip")

        XCTAssertTrue(ShareNaming.applies(.jpeg, to: [heic]))
        XCTAssertFalse(ShareNaming.applies(.jpeg, to: [jpg]), "already a JPEG")
        XCTAssertTrue(ShareNaming.applies(.smallerImage, to: [jpg, heic]))
        XCTAssertFalse(ShareNaming.applies(.smallerImage, to: [jpg, pdf]))
        XCTAssertTrue(ShareNaming.applies(.smallerPDF, to: [pdf]))
        XCTAssertTrue(ShareNaming.applies(.zip, to: [folder, pdf]))
        XCTAssertFalse(ShareNaming.applies(.zip, to: []))
    }

    func testSmallerSizesKeepTheShape() {
        XCTAssertTrue(ShareNaming.smallerSide(width: 4032, height: 3024) == (2048, 1536))
        XCTAssertTrue(ShareNaming.smallerSide(width: 1000, height: 3000) == (683, 2048))
        XCTAssertTrue(ShareNaming.smallerSide(width: 800, height: 600) == (800, 600), "never enlarged")
    }

    func testListsAsNamesPathsTableAndCSV() {
        let items = [item("/U/Downloads/Q3, final.pdf", froms: ["https://mail.google.com/"]), item("/U/Docs/Taxes", folder: true)]
        XCTAssertEqual(ListExport.text(items, format: .names), "Q3, final.pdf\nTaxes")
        XCTAssertEqual(ListExport.text(items, format: .paths), "/U/Downloads/Q3, final.pdf\n/U/Docs/Taxes")
        let table = ListExport.text(items, format: .table).components(separatedBy: "\n")
        XCTAssertEqual(table.count, 3)
        XCTAssertEqual(table[0], "Name\tKind\tSize\tBytes\tDate\tDownloaded From\tFolder\tPath")
        XCTAssertTrue(table[1].hasPrefix("Q3, final.pdf\tPDF\t"), table[1])
        XCTAssertTrue(table[1].contains("\t1500000\t"))
        XCTAssertTrue(table[1].hasSuffix("\tGmail\tDownloads\t/U/Downloads/Q3, final.pdf"), table[1])
        let csv = ListExport.text(items, format: .csv)
        XCTAssertTrue(csv.contains("\"Q3, final.pdf\",PDF,"), csv)
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertEqual(ListExport.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"", "quotes inside a cell are doubled")
        XCTAssertEqual(ListExport.csvCell("plain"), "plain")
        XCTAssertEqual(ListExport.csvCell("a,\"b\""), "\"a,\"\"b\"\"\"")
    }

    func testRecentFoldersComeFromTheNewestFiles() {
        let items = [item("/U/Downloads/a"), item("/U/Desktop/b"), item("/U/Downloads/c"), item("/U/Docs/Taxes", folder: true),
                     item("/U/Pictures/Trips/d")]
        XCTAssertEqual(RecentFolders.list(items), ["/U/Downloads", "/U/Desktop", "/U/Pictures/Trips"])
        XCTAssertEqual(RecentFolders.list(items, limit: 2, skip: ["/U/Desktop"]), ["/U/Downloads", "/U/Pictures/Trips"])
    }

    func testNewActivityKindsReadWell() {
        let renamed = ActivityEntry(action: .renamed, reason: "Renamed by you", moves: [.init(from: "/a/x.png", to: "/a/y.png")])
        XCTAssertEqual(renamed.summary, "Renamed x.png")
        let made = ActivityEntry(action: .created, reason: "Make Shareable", moves: [.init(from: "/a/x.heic", to: "/a/x.jpg")])
        XCTAssertEqual(made.summary, "Made “x.jpg”")
        let many = ActivityEntry(action: .created, reason: "Make Shareable", moves: [.init(from: "/a", to: "/b"), .init(from: "/c", to: "/d")])
        XCTAssertEqual(many.summary, "Made 2 files")
        XCTAssertTrue(FileKind.presentation.hasReadableText)
    }
    func testDateStampsMatchDateFormatterAcrossTimeZones() {
        // Zones with summer time, half-hour offsets and a half-hour summer shift.
        var zonesChecked = 0
        for name in ["UTC", "America/New_York", "Europe/London", "Asia/Kolkata", "America/St_Johns", "Australia/Lord_Howe", "Asia/Kathmandu"] {
            guard let zone = TimeZone(identifier: name) else { continue }
            zonesChecked += 1
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = zone
            f.dateFormat = "yyyy-MM-dd HH:mm"
            let from = -631_152_000.0 // 1950
            let to = 4_102_444_800.0 // 2100
            let stamp = DateStamp(from: from, to: to, zone: zone)
            var rng = SystemRandomNumberGenerator()
            var times = (0..<3_000).map { _ in Double.random(in: from...to, using: &rng) }
            // Right around summer-time changes, and at midnight and leap days.
            var t = Date(timeIntervalSince1970: 1_600_000_000)
            for _ in 0..<12 {
                guard let next = zone.nextDaylightSavingTimeTransition(after: t) else { break }
                let s = next.timeIntervalSince1970
                times += [s - 61, s - 1, s, s + 1, s + 59.5]
                t = next
            }
            times += [951_782_400, 951_868_799, 0, -0.5, 1_709_164_800, 4_102_444_799]
            for x in times {
                let date = Date(timeIntervalSince1970: x)
                XCTAssertEqual(stamp.string(date), f.string(from: date), "\(name) at \(x)")
            }
        }
        XCTAssertGreaterThan(zonesChecked, 5)
    }

    func testBigTablesMatchTheOneByOneVersion() {
        var items: [FileItem] = []
        for i in 0..<9_000 {
            let when = Date(timeIntervalSince1970: 1_500_000_000 + Double(i) * 7_919.3)
            items.append(FileItem(path: "/U/Downloads/f\(i)\(i % 7 == 0 ? ",x" : "")\(i % 11 == 0 ? "\tt" : "").pdf", size: Int64(i) * 9_973,
                                  created: when, modified: when, whereFroms: i % 3 == 0 ? ["https://mail.google.com/"] : [],
                                  isDirectory: i % 50 == 0))
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for csv in [false, true] {
            // A DateFormatter makes it go one row at a time; without one, slices are written in parallel.
            XCTAssertEqual(ListExport.table(items, csv: csv, dateFormatter: nil), ListExport.table(items, csv: csv, dateFormatter: f))
        }
        XCTAssertEqual(ListExport.tsvCell("a\tb\nc\rd"), "a b c d")
        XCTAssertEqual(ListExport.tsvCell("plain"), "plain")
        XCTAssertEqual(ListExport.csvCell(" padded"), "\" padded\"")
    }

    func testSizesReadLikeFinder() {
        XCTAssertEqual(ByteSize.format(0), "0 bytes")
        XCTAssertEqual(ByteSize.format(1_000), "1 KB")
        XCTAssertEqual(ByteSize.format(1_049), "1.0 KB")
        XCTAssertEqual(ByteSize.format(1_050), "1.1 KB")
        XCTAssertEqual(ByteSize.format(9_960_000), "10.0 MB")
        XCTAssertEqual(ByteSize.format(99_960_000), "100.0 MB")
        XCTAssertEqual(ByteSize.format(100_400_000), "100 MB")
        XCTAssertEqual(ByteSize.format(999_600), "1000 KB")
        XCTAssertEqual(ByteSize.format(2_500_000_000_000), "2.5 TB")
    }
}
