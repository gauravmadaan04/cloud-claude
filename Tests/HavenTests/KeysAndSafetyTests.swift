import AppKit
import HavenCore
import XCTest
@testable import Haven

/// Keyboard selection, paste, Put Back and live updates, inside the app on a real Mac. Everything happens in a
/// temporary folder the test creates.
final class KeysAndSafetyTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    func resetModel() {
        AppModel.shared.setVisible([])
        AppModel.shared.selectedIDs = []
    }

    func file(_ name: String, _ contents: String = "x") throws -> String {
        let p = dir.appendingPathComponent(name).path
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: p))
        return p
    }

    func items(_ names: [String]) -> [FileItem] {
        names.map { FileItem(path: "/sample/" + $0, created: Date(), modified: Date()) }
    }

    @MainActor
    func testArrowsAndShiftArrowsInTheGrid() {
        let model = AppModel.shared
        let saved = Prefs.shared.viewMode
        Prefs.shared.viewMode = .grid
        defer {
            Prefs.shared.viewMode = saved
            resetModel()
        }
        let list = items((0..<9).map { "f\($0).txt" })
        model.setVisible(list)
        model.gridColumns = 3
        model.selectedIDs = [list[0].id]
        model.selectionAnchor = list[0].id
        model.selectionLead = list[0].id

        XCTAssertTrue(model.moveSelection(.right, extend: false))
        XCTAssertEqual(model.selectedIDs, [list[1].id])
        XCTAssertTrue(model.moveSelection(.down, extend: false))
        XCTAssertEqual(model.selectedIDs, [list[4].id], "down moves a whole row")
        XCTAssertTrue(model.moveSelection(.right, extend: true))
        XCTAssertTrue(model.moveSelection(.right, extend: true))
        XCTAssertEqual(model.selectedIDs, Set(list[4...6].map(\.id)), "⇧→ grows the selection from where it started")
        XCTAssertTrue(model.moveSelection(.left, extend: true))
        XCTAssertEqual(model.selectedIDs, Set(list[4...5].map(\.id)), "⇧← shrinks it again")
        XCTAssertTrue(model.moveSelection(.up, extend: false))
        XCTAssertEqual(model.selectedIDs, [list[2].id])
    }

    @MainActor
    func testTypingANameSelectsIt() {
        let model = AppModel.shared
        let list = items(["Zoom-6.2.pkg", "invoice-4821.png", "Invoice 2.pdf", "holiday-photos", "holiday-photos.zip"])
        model.setVisible(list)
        defer { resetModel() }
        XCTAssertTrue(model.typeAhead("i"))
        XCTAssertEqual(model.selectedItems.map(\.name), ["Invoice 2.pdf"], "first in name order")
        XCTAssertTrue(model.typeAhead("nvoice-"))
        XCTAssertEqual(model.selectedItems.map(\.name), ["invoice-4821.png"], "keys typed together add up")
        Thread.sleep(forTimeInterval: 1.1)
        XCTAssertTrue(model.typeAhead("h"))
        XCTAssertEqual(model.selectedItems.map(\.name), ["holiday-photos"], "a pause starts a new name")
    }

    @MainActor
    func testSelectionSurvivesAndDropsWithTheList() {
        let model = AppModel.shared
        let list = items(["a.txt", "b.txt", "c.txt"])
        model.setVisible(list)
        defer { resetModel() }
        model.selectedIDs = [list[0].id, list[2].id]
        model.setVisible(Array(list.prefix(2)))
        XCTAssertEqual(model.selectedIDs, [list[0].id], "files that left the list leave the selection")
        XCTAssertEqual(model.selectedItems.map(\.name), ["a.txt"])
    }

    @MainActor
    func testQuickLookOnlyGetsTheFilesAroundTheCurrentOne() {
        let list = items((0..<3_000).map { "f\($0).txt" })
        let urls = AppModel.window(around: list[1_500].url, in: list)
        XCTAssertEqual(urls.count, 1_000)
        XCTAssertTrue(urls.contains(list[1_500].url))
    }

    @MainActor
    func testPasteMakesCopiesAndNeverReplaces() async throws {
        let src = try file("from/report.pdf", "original")
        let target = dir.appendingPathComponent("to").path
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        let existing = try file("to/report.pdf", "keep me")

        FileOps.shared.copy([URL(fileURLWithPath: src)], into: target)
        FileOps.shared.copy([URL(fileURLWithPath: src)], into: target)
        var names: [String] = []
        for _ in 0..<80 {
            names = (try? FileManager.default.contentsOfDirectory(atPath: target)) ?? []
            if names.count == 3 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(Set(names), ["report.pdf", "report 2.pdf", "report 3.pdf"])
        XCTAssertEqual(try String(contentsOfFile: existing, encoding: .utf8), "keep me", "the file already there is untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src), "pasting copies, the original stays")
    }

    @MainActor
    func testPutBackOnlyMovesTheSameFile() throws {
        let p = try file("put-back.txt", "one")
        let id = FileOps.fileID(p)
        let move = ActivityEntry.Move(from: "/elsewhere/put-back.txt", to: p, size: 3, fileID: id)
        XCTAssertTrue(FileOps.isStillThere(move))
        // A different file now has that name: Put Back must leave it alone.
        try FileManager.default.moveItem(atPath: p, toPath: p + ".moved")
        _ = try file("put-back.txt", "two")
        XCTAssertFalse(FileOps.isStillThere(move))
    }

    @MainActor
    func testTrashingAFolderAndItsFileTogetherPutsBothBack() throws {
        let inner = try file("Album/photo.jpg")
        let folder = (inner as NSString).deletingLastPathComponent
        let fileItem = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: inner), rootID: "t"))
        let folderItem = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: folder, isDirectory: true), rootID: "t"))
        let entry = try XCTUnwrap(FileOps.shared.trash([fileItem, folderItem], reason: "Test", announce: false, undoable: false))
        XCTAssertEqual(entry.moves.count, 1, "the file goes along with its folder")
        FileOps.shared.undo(entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inner), "the folder comes back with the file inside")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder + " 2"))
    }

    @MainActor
    func testRelistingAFolderPicksUpChanges() throws {
        let a = try file("Downloads/a.txt")
        let b = try file("Downloads/b.txt")
        let downloads = (a as NSString).deletingLastPathComponent
        let root = IndexRoot(id: "downloads", path: downloads, name: "Downloads")
        let base = FileScanner.scan(root: root)
        XCTAssertEqual(Set(base.map(\.name)), ["a.txt", "b.txt"])
        try FileManager.default.removeItem(atPath: b)
        _ = try file("Downloads/c.txt")
        _ = try file("Downloads/New Folder/inside.txt")
        _ = try file("Downloads/node_modules/skip.js")
        let result = LibraryStore.relist([downloads], deep: [], base: base, roots: [root], options: ScanOptions(), sizes: [:])
        XCTAssertEqual(Set(result.items.map(\.name)), ["a.txt", "c.txt", "New Folder", "inside.txt"])
    }
}
