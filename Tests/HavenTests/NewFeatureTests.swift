// Uses the sample-file generator, which only exists in debug builds.
#if DEBUG
import AppKit
import HavenCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Haven

/// Renaming, Make Shareable, office text, collections, the shelf and rules, on real files in a temporary folder.
final class NewFeatureTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

    @discardableResult
    func make(_ name: String, _ text: String = "x") -> String {
        let p = path(name)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: URL(fileURLWithPath: p))
        return p
    }

    func item(_ p: String) -> FileItem { FileScanner.item(at: URL(fileURLWithPath: p), rootID: "t")! }
    func read(_ p: String) -> String? { try? String(contentsOfFile: p, encoding: .utf8) }
    func names(in folder: String? = nil) -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: folder ?? dir.path)) ?? []) }

    func pixelSize(_ p: String) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    // MARK: Rename

    @MainActor
    func testRenameThenUndoPutsEveryNameBack() async throws {
        let items = ["IMG_1.jpg", "IMG_2.jpg", "notes.txt"].map { item(make($0)) }
        let changes = await RenameService.plan(items, template: RenameTemplate(pattern: "Trip {n:2}"))
        XCTAssertEqual(changes.map(\.newName), ["Trip 01.jpg", "Trip 02.jpg", "Trip 03.txt"])
        let entry = try XCTUnwrap(FileOps.shared.rename(changes, announce: false, undoable: false))
        XCTAssertEqual(entry.action, .renamed)
        XCTAssertEqual(names(), ["Trip 01.jpg", "Trip 02.jpg", "Trip 03.txt"])
        FileOps.shared.undo(entry.id)
        XCTAssertEqual(names(), ["IMG_1.jpg", "IMG_2.jpg", "notes.txt"])
    }

    @MainActor
    func testSwappedNamesAndCaseOnlyChanges() throws {
        let a = make("a.txt", "AAA"), b = make("b.txt", "BBB")
        let swap = [RenameChange(item: item(a), newName: "b.txt", adjusted: false), RenameChange(item: item(b), newName: "a.txt", adjusted: false)]
        let entry = try XCTUnwrap(FileOps.shared.rename(swap, announce: false, undoable: false))
        XCTAssertEqual(read(a), "BBB")
        XCTAssertEqual(read(b), "AAA")
        XCTAssertEqual(names(), ["a.txt", "b.txt"], "no temporary names left behind")
        FileOps.shared.undo(entry.id)
        XCTAssertEqual(read(a), "AAA")
        XCTAssertEqual(read(b), "BBB")

        let c = make("photo.txt", "C")
        XCTAssertNotNil(FileOps.shared.rename([RenameChange(item: item(c), newName: "Photo.txt", adjusted: false)], announce: false, undoable: false))
        XCTAssertTrue(names().contains("Photo.txt"))
        XCTAssertFalse(names().contains("photo.txt"))
    }

    @MainActor
    func testRenameNeverReplacesAFileThatAppearedMeanwhile() {
        let a = make("a.txt", "mine")
        let changes = RenamePlanner.plan([item(a)], template: RenameTemplate(pattern: "taken")) { _ in ["a.txt"] }
        make("taken.txt", "someone else's")
        XCTAssertNil(FileOps.shared.rename(changes, announce: false, undoable: false))
        XCTAssertEqual(read(path("taken.txt")), "someone else's")
        XCTAssertEqual(read(a), "mine")
    }

    func testSmartTitlesFromRealOCR() throws {
        let shot = path("Screenshot 2026-10-12 at 09.41.22.png")
        FixtureFactory.image(lines: ["Boarding Pass", "DEL → BOM · Gate 42"], palette: [0x2B78E4, 0x64A6FF], size: CGSize(width: 1600, height: 1000), to: shot)
        let text = try XCTUnwrap(TextExtractor.recognizeText(in: URL(fileURLWithPath: shot)))
        XCTAssertEqual(SmartTitle.title(from: text), "Boarding Pass", text)
    }

    // MARK: Make Shareable

    func testJPEGCopiesLeaveTheOriginalAlone() throws {
        let heic = path("IMG_1.heic")
        FixtureFactory.scene(seed: 3, size: CGSize(width: 1200, height: 900), to: heic, type: .heic)
        let before = try Data(contentsOf: URL(fileURLWithPath: heic))
        let o = ShareMaker.make(.jpeg, items: [item(heic)])
        XCTAssertEqual(o.made.count, 1)
        let jpg = try XCTUnwrap(o.made.first?.to)
        XCTAssertEqual((jpg as NSString).lastPathComponent, "IMG_1.jpg")
        XCTAssertEqual(UTType(filenameExtension: "jpg"), .jpeg)
        XCTAssertTrue(pixelSize(jpg)! == (1200, 900))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: heic)), before, "the original is untouched")
        // A second copy never replaces the first.
        XCTAssertEqual(ShareMaker.make(.jpeg, items: [item(heic)]).made.first.map { ($0.to as NSString).lastPathComponent }, "IMG_1 2.jpg")
    }

    func testTransparentImagesGetAWhiteBackground() throws {
        let png = path("logo.png")
        let size = CGSize(width: 200, height: 200)
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 80, width: 40, height: 40))
        FixtureFactory.save(ctx.makeImage()!, to: png, type: .png)
        let jpg = try XCTUnwrap(ShareMaker.make(.jpeg, items: [item(png)]).made.first?.to)
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: jpg) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        probe.draw(image, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]), 700, "the corner is white, not black")
    }

    func testSmallerImagesKeepTheirShape() throws {
        let big = path("Big Photo.jpg")
        FixtureFactory.scene(seed: 2, size: CGSize(width: 4000, height: 3000), to: big, type: .jpeg)
        let o = ShareMaker.make(.smallerImage, items: [item(big)])
        let small = try XCTUnwrap(o.made.first?.to)
        XCTAssertEqual((small as NSString).lastPathComponent, "Big Photo (small).jpg")
        XCTAssertTrue(pixelSize(small)! == (2048, 1536))
        XCTAssertLessThan(o.bytesAfter, o.bytesBefore)
    }

    func testSmallerPDFsAndPDFsThatAreAlreadySmall() throws {
        // A page with a big photo of noise (stored losslessly): plenty to save.
        let heavy = path("Scan.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(URL(fileURLWithPath: heavy) as CFURL, mediaBox: &box, nil))
        let w = 2200, h = 2200
        var noise = [UInt8](repeating: 0, count: w * h * 4)
        var x: UInt32 = 2_463_534_242
        for i in stride(from: 0, to: noise.count, by: 4) {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5
            noise[i] = UInt8(truncatingIfNeeded: x); noise[i + 1] = UInt8(truncatingIfNeeded: x >> 8)
            noise[i + 2] = UInt8(truncatingIfNeeded: x >> 16); noise[i + 3] = 255
        }
        let provider = CGDataProvider(data: Data(noise) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: CGRect(x: 36, y: 36, width: 540, height: 540))
        pdf.endPDFPage()
        pdf.closePDF()
        let o = ShareMaker.make(.smallerPDF, items: [item(heavy)])
        print("PDF: \(o.bytesBefore) → \(o.bytesAfter) bytes, made \(o.made.count), already small \(o.alreadySmall)")
        let smaller = try XCTUnwrap(o.made.first?.to, "the PDF should get smaller")
        XCTAssertEqual((smaller as NSString).lastPathComponent, "Scan (smaller).pdf")
        XCTAssertLessThan(o.bytesAfter, o.bytesBefore / 2)
        XCTAssertEqual(PDFDocument(url: URL(fileURLWithPath: smaller))?.pageCount, 1)

        let light = path("Letter.pdf")
        FixtureFactory.pdf(lines: ["Dear friend", "Short letter"], to: light)
        let o2 = ShareMaker.make(.smallerPDF, items: [item(light)])
        XCTAssertTrue(o2.made.isEmpty)
        XCTAssertEqual(o2.alreadySmall, 1)
        XCTAssertFalse(names().contains("Letter (smaller).pdf"), "nothing is left behind")
    }

    func testZipsOfOneAndOfSeveral() throws {
        let a = make("a.txt", String(repeating: "hello ", count: 500))
        let b = make("Trip/b.txt", "inside")
        let folder = item(path("Trip"))
        let one = ShareMaker.make(.zip, items: [item(a)])
        XCTAssertEqual(one.made.first.map { ($0.to as NSString).lastPathComponent }, "a.txt.zip")
        let many = ShareMaker.make(.zip, items: [item(a), folder])
        let zipPath = try XCTUnwrap(many.made.first?.to)
        XCTAssertEqual((zipPath as NSString).lastPathComponent, "Archive.zip")
        let names = try ZipArchive(url: URL(fileURLWithPath: zipPath)).entries.map(\.name)
        XCTAssertTrue(names.contains("a.txt"), "\(names)")
        XCTAssertTrue(names.contains("Trip/b.txt"), "\(names)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b), "originals stay")
    }

    @MainActor
    func testUndoingCopiesMovesThemToTheTrash() throws {
        let heic = path("IMG_9.heic")
        FixtureFactory.scene(seed: 4, size: CGSize(width: 600, height: 400), to: heic, type: .heic)
        let o = ShareMaker.make(.jpeg, items: [item(heic)])
        let entry = try XCTUnwrap(FileOps.shared.recordCreated(o.made, reason: "Save as JPEG"))
        XCTAssertEqual(entry.action, .created)
        FileOps.shared.undo(entry.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("IMG_9.jpg")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: heic))
    }

    // MARK: Text in more kinds of files

    func testOfficeIWorkAndWebPagesAreRead() throws {
        let docx = path("Lease.docx")
        try TestZip.write([("word/document.xml", "<w:document><w:body><w:p><w:r><w:t>Rental agreement for Priya</w:t></w:r></w:p></w:body></w:document>")], to: docx)
        let pptx = path("Pitch.pptx")
        try TestZip.write([("ppt/slides/slide1.xml", "<p:sld><a:p><a:r><a:t>Launch plan</a:t></a:r></a:p></p:sld>"),
                           ("ppt/slides/slide2.xml", "<p:sld><a:p><a:r><a:t>Mango season</a:t></a:r></a:p></p:sld>")], to: pptx)
        let xlsx = path("Budget.xlsx")
        try TestZip.write([("xl/sharedStrings.xml", "<sst><si><t>Groceries</t></si><si><t>Rent</t></si></sst>")], to: xlsx)
        let html = make("page.html", "<html><head><style>p{}</style></head><body><p>Hello <b>there</b></p><script>x()</script></body></html>")
        // A Pages file carries a picture of its first page.
        let preview = path("preview-source.jpg")
        FixtureFactory.image(lines: ["Quarterly Plan", "Phase one: research"], palette: [0xFFFFFF, 0xF4F4F4], dark: true,
                             size: CGSize(width: 1400, height: 1000), to: preview)
        let pages = path("Plan.pages")
        try TestZip.write([("Index/Document.iwa", Data("binary".utf8)), ("preview.jpg", try Data(contentsOf: URL(fileURLWithPath: preview)))], to: pages)

        XCTAssertEqual(TextExtractor.extract(item(docx)), "Rental agreement for Priya")
        XCTAssertEqual(TextExtractor.extract(item(pptx)), "Launch plan\nMango season")
        XCTAssertEqual(TextExtractor.extract(item(xlsx)), "Groceries\nRent")
        XCTAssertEqual(TextExtractor.extract(item(html)), "Hello there")
        let pagesText = try XCTUnwrap(TextExtractor.extract(item(pages)))
        XCTAssertTrue(pagesText.contains("Quarterly"), pagesText)

        let all = [docx, pptx, xlsx, pages].map(item)
        XCTAssertEqual(Set(TextIndex.candidates(all, scope: .recent).map(\.name)), ["Lease.docx", "Pitch.pptx", "Budget.xlsx", "Plan.pages"])
    }

    // MARK: Collections and shelf

    @MainActor
    func testCollectionsFollowRenamesAndFindFilesMovedElsewhere() async throws {
        let a = make("a.txt")
        let id = CollectionStore.shared.create(name: "Test \(UUID().uuidString.prefix(6))", paths: [a])
        defer { CollectionStore.shared.delete(id) }
        FileOps.shared.rename([RenameChange(item: item(a), newName: "b.txt", adjusted: false)], announce: false, undoable: false)
        XCTAssertEqual(CollectionStore.shared.collection(id)?.paths, [path("b.txt")], "renames made in Haven are followed")

        // Moved by something else: the bookmark finds it.
        let c = make("c.txt")
        CollectionStore.shared.add([c], to: id)
        for _ in 0..<50 where CollectionStore.shared.collection(id)?.entries.last?.bookmark == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        try FileManager.default.createDirectory(atPath: path("Moved"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(atPath: c, toPath: path("Moved/c.txt"))
        let found = await CollectionStore.shared.findMissing(in: id, missing: [c])
        XCTAssertEqual(found, 1)
        XCTAssertEqual(CollectionStore.shared.collection(id)?.paths.last, path("Moved/c.txt"))
    }

    @MainActor
    func testShelfKeepsEachFileOnceAndDropsDeletedOnes() throws {
        let shelf = ShelfStore.shared
        let saved = shelf.urls
        defer {
            shelf.clear()
            shelf.add(saved)
        }
        shelf.clear()
        let a = make("a.txt")
        XCTAssertEqual(shelf.add([URL(fileURLWithPath: a), URL(fileURLWithPath: a)]), 1)
        XCTAssertEqual(shelf.add([URL(fileURLWithPath: a)]), 0)
        try FileManager.default.removeItem(atPath: a)
        shelf.prune()
        XCTAssertTrue(shelf.urls.isEmpty)
    }

    // MARK: Rules

    @MainActor
    func testARuleFilesMatchingDownloadsAndCanBeUndone() throws {
        let downloads = path("Downloads")
        let invoice = make("Downloads/invoice-1.pdf", "pdf")
        make("Downloads/holiday.jpg", "jpg")
        for p in [invoice, path("Downloads/holiday.jpg")] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: p)
        }
        let rule = CustomRule(name: "Invoices", folders: [downloads], conditions: [.nameContains("invoice")],
                              action: .move(to: path("Documents/Invoices"), byMonth: false))
        let items = FileScanner.scan(root: IndexRoot(id: "t", path: downloads, name: "Downloads"))
        let steps = CustomRulePlanner.plan(rule, items: items)
        XCTAssertEqual(steps.map(\.item.name), ["invoice-1.pdf"])
        let entry = try XCTUnwrap(FileOps.shared.move(steps.map { (item: $0.item, directory: $0.destination!) }, reason: "Rule · Invoices"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("Documents/Invoices/invoice-1.pdf")))
        FileOps.shared.undo(entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: invoice))
    }

    // MARK: Space, lists, dialog keys

    func testFolderSizesInTheDerivedIndex() {
        make("Space/a.bin", String(repeating: "a", count: 1000))
        make("Space/deep/b.bin", String(repeating: "b", count: 500))
        let root = path("Space")
        let items = FileScanner.scan(root: IndexRoot(id: "t", path: root, name: "Space"))
        let d = LibraryDerived.compute(items, cleanup: CleanupSettings(), tops: [root])
        XCTAssertEqual(d.folderSizes[root]?.bytes, 1500)
        XCTAssertEqual(d.folderSizes[root]?.files, 2)
        XCTAssertEqual(d.folderSizes[path("Space/deep")]?.bytes, 500)
        XCTAssertEqual(d.space.totalBytes, 1500)
    }

    @MainActor
    func testCopyListPutsATableOnTheClipboard() {
        let items = [item(make("one.txt")), item(make("two.txt"))]
        AppModel.shared.copyList(.table, items)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(text.hasPrefix("Name\tKind\tSize"), text)
        XCTAssertTrue(text.contains("one.txt\tText"), text)
    }

    func testDialogTypingNeverSplitsACharacter() {
        let p = "/Users/me/Documents/Résumé 📸 folder/日本"
        for size in [1, 2, 3, 4, 16] {
            let chunks = KeyText.chunks(p, size: size)
            XCTAssertEqual(String(decoding: chunks.flatMap { $0 }, as: UTF16.self), p)
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && !UTF16.isTrailSurrogate($0[0]) })
        }
    }
}

/// A tiny ZIP writer (stored, not compressed) for making office-style files in tests.
enum TestZip {
    static func write(_ files: [(String, String)], to path: String) throws {
        try write(files.map { ($0.0, Data($0.1.utf8)) }, to: path)
    }

    static func write(_ files: [(String, Data)], to path: String) throws {
        var out = Data()
        var central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: UInt32, _ d: inout Data) { for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        for (name, data) in files {
            let offset = UInt32(out.count)
            let crc = crc32(data)
            let n = Data(name.utf8)
            u32(0x0403_4B50, &out); u16(20, &out); u16(0, &out); u16(0, &out); u16(0, &out); u16(0, &out)
            u32(crc, &out); u32(UInt32(data.count), &out); u32(UInt32(data.count), &out); u16(n.count, &out); u16(0, &out)
            out.append(n); out.append(data)
            u32(0x0201_4B50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(crc, &central); u32(UInt32(data.count), &central); u32(UInt32(data.count), &central); u16(n.count, &central)
            u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central.append(n)
        }
        let dirOffset = UInt32(out.count)
        out.append(central)
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(dirOffset, &out); u16(0, &out)
        try out.write(to: URL(fileURLWithPath: path))
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}
#endif
