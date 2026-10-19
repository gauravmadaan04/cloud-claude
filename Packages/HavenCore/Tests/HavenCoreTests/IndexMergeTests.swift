import Foundation
@testable import HavenCore
import XCTest

final class IndexMergeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func f(_ path: String, _ minutes: Double, folder: Bool = false) -> FileItem {
        let d = t0.addingTimeInterval(minutes * 60)
        return FileItem(path: path, created: d, modified: d, rootID: "r", isDirectory: folder)
    }

    func newestFirst(_ items: [FileItem]) -> [FileItem] { FileSortOrder.dateNewest.sorted(items) }

    func testRelistedFolderReplacesItsChildrenAndDropsRemovedSubfolders() {
        let base = newestFirst([
            f("/r/a", 1, folder: true), f("/r/a/a1.txt", 2), f("/r/a/a2.txt", 3), f("/r/a/sub", 4, folder: true),
            f("/r/a/sub/s1.txt", 5), f("/r/a/sub/deeper/s2.txt", 6), f("/r/b", 7, folder: true), f("/r/b/b1.txt", 8),
            f("/r/ab.txt", 9),
        ])
        let merged = IndexMerge.apply(base: base, listed: ["/r/a": [f("/r/a/a1.txt", 20), f("/r/a/a3.txt", 0.5)]])
        XCTAssertEqual(Set(merged.map(\.path)), ["/r/a", "/r/a/a1.txt", "/r/a/a3.txt", "/r/b", "/r/b/b1.txt", "/r/ab.txt"])
        XCTAssertEqual(merged.first?.path, "/r/a/a1.txt", "the changed file moves to the top")
        XCTAssertEqual(merged.map(\.path), newestFirst(merged).map(\.path))
    }

    func testGoneFolderTakesEverythingInside() {
        let base = newestFirst([f("/r/b", 1, folder: true), f("/r/b/x.txt", 2), f("/r/b/c/y.txt", 3), f("/r/bb.txt", 4)])
        let merged = IndexMerge.apply(base: base, listed: [:], gone: ["/r/b"])
        XCTAssertEqual(merged.map(\.path), ["/r/bb.txt"])
    }

    func testNewSubfolderBringsItsSubtree() {
        let base = newestFirst([f("/r/b", 1, folder: true), f("/r/b/old.txt", 2)])
        let merged = IndexMerge.apply(base: base,
                                      listed: ["/r/b": [f("/r/b/old.txt", 2), f("/r/b/new", 30, folder: true)]],
                                      added: [f("/r/b/new/one.txt", 31), f("/r/b/new/two/three.txt", 29)])
        XCTAssertEqual(merged.map(\.path), ["/r/b/new/one.txt", "/r/b/new", "/r/b/new/two/three.txt", "/r/b/old.txt", "/r/b"])
    }

    func testRemovingTrashedFolderDropsItsContents() {
        let base = newestFirst([f("/r/p", 1, folder: true), f("/r/p/q.txt", 2), f("/r/pq.txt", 3), f("/r/z.txt", 4)])
        XCTAssertEqual(IndexMerge.removing(["/r/p"], from: base).map(\.path), ["/r/z.txt", "/r/pq.txt"])
        XCTAssertEqual(IndexMerge.removing(["/r/z.txt"], from: base).count, 3)
    }

    func testMergeKeepsOrderOnALargeLibrary() {
        let base = FileSortOrder.dateNewest.sorted(SyntheticLibrary.make(count: 20_000, seed: 11))
        let dir = base[10].parentPath
        let children = base.filter { $0.parentPath == dir }
        let touched = children.prefix(3).map { item in
            FileItem(path: item.path, size: item.size + 1, created: item.created, modified: Date(), rootID: item.rootID)
        }
        let merged = IndexMerge.apply(base: base, listed: [dir: Array(touched)])
        XCTAssertEqual(merged.count, base.count - children.count + touched.count)
        XCTAssertEqual(merged.map(\.path), FileSortOrder.dateNewest.sorted(merged).map(\.path))
        XCTAssertEqual(Set(merged.prefix(3).map(\.path)), Set(touched.map(\.path)))
    }

    func testListingSkipsTheFoldersAScanSkips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("haven-list-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Photos.noindex"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Real Folder"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("note.txt"))
        defer { try? fm.removeItem(at: root) }
        let names = Set(FileScanner.list(directory: root.path, rootID: "r").map(\.name))
        #if os(macOS)
        XCTAssertEqual(names, ["Real Folder", "note.txt"])
        #else
        // Foundation on Linux calls any folder with an extension a package, so only node_modules is checked.
        XCTAssertFalse(names.contains("node_modules"))
        XCTAssertTrue(names.isSuperset(of: ["Real Folder", "note.txt"]))
        #endif
        let listed = FileScanner.list(directory: root.path, rootID: "r").first { $0.name == "note.txt" }
        XCTAssertEqual(listed?.searchParent, FileItem.fold(root.lastPathComponent))
    }
}
