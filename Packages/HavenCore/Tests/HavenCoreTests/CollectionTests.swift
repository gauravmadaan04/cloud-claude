import Foundation
@testable import HavenCore
import XCTest

final class CollectionTests: XCTestCase {
    func item(_ path: String) -> FileItem { FileItem(path: path, created: Date(), modified: Date()) }

    func testAddRemoveAndNoDoubles() {
        var c = FileCollection(name: "Trip")
        XCTAssertEqual(c.add(["/a/1.jpg", "/a/2.jpg", "/a/1.jpg"]), 2)
        XCTAssertEqual(c.add(["/a/2.jpg", "/a/3.jpg"]), 1)
        XCTAssertEqual(c.paths, ["/a/1.jpg", "/a/2.jpg", "/a/3.jpg"])
        XCTAssertEqual(c.remove(["/a/2.jpg", "/nope"]), 1)
        XCTAssertEqual(c.paths, ["/a/1.jpg", "/a/3.jpg"])
        XCTAssertTrue(c.contains("/a/3.jpg"))
    }

    func testEntriesFollowRenamesAndFolderMoves() {
        var c = FileCollection(name: "Work")
        c.add(["/d/report.pdf", "/d/Project/plan.pdf", "/d/Project/sub/x.png", "/d/Projects2/y.png"])
        XCTAssertTrue(c.follow(["/d/report.pdf": "/d/2026-10-12 report.pdf", "/d/Project": "/e/Project"]))
        XCTAssertEqual(c.paths, ["/d/2026-10-12 report.pdf", "/e/Project/plan.pdf", "/e/Project/sub/x.png", "/d/Projects2/y.png"],
                       "a folder move carries what's inside it, but not folders that only start with the same name")
        XCTAssertFalse(c.follow(["/zzz": "/yyy"]))
        // Moving one listed file onto another listed path keeps a single entry.
        var d = FileCollection(name: "x")
        d.add(["/a", "/b"])
        d.follow(["/a": "/b"])
        XCTAssertEqual(d.paths, ["/b"])
    }

    func testResolveFindsIndexedFilesAndReportsMissing() {
        var c = FileCollection(name: "x")
        c.add(["/d/a.pdf", "/d/gone.pdf", "/d/c.pdf"])
        let index = [item("/d/c.pdf"), item("/d/b.pdf"), item("/d/a.pdf")]
        let r = c.resolve(in: index)
        XCTAssertEqual(Set(r.found.map(\.path)), ["/d/a.pdf", "/d/c.pdf"])
        XCTAssertEqual(r.missing, ["/d/gone.pdf"])
    }

    func testFreeNames() {
        XCTAssertEqual(FileCollection.freeName("Collection", among: []), "Collection")
        XCTAssertEqual(FileCollection.freeName("Collection", among: ["collection", "Collection 2"]), "Collection 3")
    }

    func testResolvingInABigIndexIsQuick() {
        let index = SyntheticLibrary.make(count: 100_000)
        var c = FileCollection(name: "x")
        c.add(stride(from: 0, to: 100_000, by: 500).map { index[$0].path })
        let start = Date()
        let r = c.resolve(in: index)
        XCTAssertEqual(r.found.count, 200)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
