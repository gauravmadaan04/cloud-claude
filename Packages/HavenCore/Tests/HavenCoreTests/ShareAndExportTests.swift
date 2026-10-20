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
}
