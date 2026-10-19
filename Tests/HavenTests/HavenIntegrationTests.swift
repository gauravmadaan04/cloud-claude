import AppKit
import HavenCore
import XCTest
@testable import Haven

/// Runs inside the app on a real Mac: Vision OCR, PDFKit, extended attributes, Quick Look, Trash.
final class HavenIntegrationTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

    func testOCRReadsTextInImages() throws {
        let p = path("card.png")
        FixtureFactory.image(lines: ["Invoice 4821", "Total due 12400"], palette: [0xFFFFFF, 0xEEEEEE], dark: true,
                             size: CGSize(width: 1400, height: 900), to: p)
        let text = try XCTUnwrap(TextExtractor.recognizeText(in: URL(fileURLWithPath: p)))
        print("OCR result:", text.replacingOccurrences(of: "\n", with: " | "))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("invoice"), text)
        XCTAssertTrue(text.contains("4821"), text)
    }

    func testPDFAndDocumentText() throws {
        let pdf = path("report.pdf")
        FixtureFactory.pdf(lines: ["Quarterly Report", "Revenue up 18%"], to: pdf)
        let pdfText = try XCTUnwrap(TextExtractor.pdfText(URL(fileURLWithPath: pdf)))
        XCTAssertTrue(pdfText.contains("Quarterly Report"), pdfText)

        let rtf = path("resume.rtf")
        FixtureFactory.richText("Product designer in Delhi", to: rtf, date: Date())
        XCTAssertTrue(TextExtractor.documentText(URL(fileURLWithPath: rtf))?.contains("designer") ?? false)

        let md = path("notes.md")
        FixtureFactory.text("Groceries: mangoes", to: md, date: Date())
        XCTAssertEqual(TextExtractor.plainText(URL(fileURLWithPath: md)), "Groceries: mangoes")
    }

    func testScannerReadsDownloadMetadata() throws {
        let p = path("attachment.pdf")
        FixtureFactory.pdf(lines: ["Hello"], to: p)
        XCTAssertTrue(XAttr.setWhereFroms(["https://mail-attachment.googleusercontent.com/x", "https://mail.google.com/"], path: p))
        XCTAssertTrue(XAttr.setQuarantine(agent: "Safari", path: p))
        let opened = Date().addingTimeInterval(-3 * 86_400)
        XCTAssertTrue(XAttr.setLastUsedDate(opened, path: p))
        let item = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: p), rootID: "downloads"))
        XCTAssertEqual(item.source?.id, "gmail")
        XCTAssertEqual(item.quarantineAgent, "Safari")
        XCTAssertEqual(item.lastOpened?.timeIntervalSince1970 ?? 0, opened.timeIntervalSince1970, accuracy: 1)

        let shot = path("Capture.png")
        FixtureFactory.image(lines: ["x"], palette: [0x000000, 0x111111], size: CGSize(width: 100, height: 100), to: shot)
        XAttr.setScreenCapture(path: shot)
        XCTAssertTrue(try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: shot), rootID: "desktop")).isScreenshot)

        let airdrop = path("photo.jpg")
        FixtureFactory.scene(seed: 1, size: CGSize(width: 200, height: 150), to: airdrop, type: .jpeg)
        XAttr.setQuarantine(agent: "sharingd", path: airdrop)
        XCTAssertEqual(FileScanner.item(at: URL(fileURLWithPath: airdrop), rootID: "downloads")?.source?.id, "airdrop")
    }

    func testFeaturePrintsSeparateLookAlikesFromDifferentPhotos() throws {
        let a = path("IMG_1.jpg"), b = path("IMG_1.heic"), c = path("other.jpg")
        FixtureFactory.scene(seed: 5, size: CGSize(width: 1200, height: 900), to: a, type: .jpeg)
        FixtureFactory.scene(seed: 5, size: CGSize(width: 1200, height: 900), to: b, type: .heic, brightness: 0.04)
        FixtureFactory.scene(seed: 2, size: CGSize(width: 1200, height: 900), to: c, type: .jpeg)
        let fa = try XCTUnwrap(SimilarPhotoFinder.featurePrint(for: URL(fileURLWithPath: a)))
        let fb = try XCTUnwrap(SimilarPhotoFinder.featurePrint(for: URL(fileURLWithPath: b)))
        let fc = try XCTUnwrap(SimilarPhotoFinder.featurePrint(for: URL(fileURLWithPath: c)))
        let same = try XCTUnwrap(SimilarPhotoFinder.distance(fa, fb))
        let different = try XCTUnwrap(SimilarPhotoFinder.distance(fa, fc))
        print("Feature print distance: look-alike \(same), different \(different), threshold \(DuplicateService.similarityThreshold)")
        XCTAssertLessThan(same, DuplicateService.similarityThreshold)
        XCTAssertGreaterThan(different, same)
    }

    func testThumbnailsAreRealPictures() async throws {
        let p = path("pic.png")
        FixtureFactory.scene(seed: 3, size: CGSize(width: 800, height: 600), to: p, type: .png)
        let item = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: p), rootID: "pictures"))
        let thumb = await Thumbnails.shared.thumbnail(for: item, side: 200, scale: 2)
        XCTAssertFalse(thumb.isIcon)
        XCTAssertGreaterThan(thumb.image.size.width, 10)
    }

    @MainActor
    func testTrashAndUndo() throws {
        let p = path("old-installer.dmg")
        FixtureFactory.bytes(size: 4096, seed: 3, to: p)
        let item = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: p), rootID: "downloads"))
        let entry = try XCTUnwrap(FileOps.shared.trash([item], reason: "Test", announce: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p))
        XCTAssertEqual(entry.moves.count, 1)
        XCTAssertTrue(FileOps.shared.canUndo(entry))
        FileOps.shared.undo(entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p), "Undo should put the file back")
    }

    @MainActor
    func testRulesMoveScreenshotsIntoMonthlyFolders() throws {
        let desktop = dir.appendingPathComponent("Desktop").path
        try FileManager.default.createDirectory(atPath: desktop, withIntermediateDirectories: true)
        let shot = (desktop as NSString).appendingPathComponent("Screenshot 2026-03-01 at 10.00.00.png")
        FixtureFactory.image(lines: ["x"], palette: [0x000000, 0x222222], size: CGSize(width: 80, height: 80), to: shot)
        let created = Date().addingTimeInterval(-40 * 86_400)
        FixtureFactory.mark(shot, date: created, screenshot: true)
        let item = try XCTUnwrap(FileScanner.item(at: URL(fileURLWithPath: shot), rootID: "desktop"))
        var settings = RuleSettings(home: dir.path)
        settings.screenshotFolder = dir.appendingPathComponent("Screenshots").path
        let plan = RulesPlanner.plan(.fileScreenshots, items: [item], settings: settings, screenshotSources: [desktop], downloadsFolder: "")
        XCTAssertEqual(plan.count, 1)
        guard case .move(let target) = plan[0].operation else { return XCTFail("expected a move") }
        let entry = try XCTUnwrap(FileOps.shared.move([(item, target)], reason: "Test rule"))
        let moved = entry.moves[0].to
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved))
        XCTAssertTrue(moved.contains(RulesPlanner.monthFolderName(for: created)))
        FileOps.shared.undo(entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot))
    }

    func testHotKeyDisplay() {
        XCTAssertEqual(HotKeyCombo.default.display, "⇧⌘Space")
        XCTAssertEqual(HotKeyCenter.symbols(UInt32(0x100 | 0x200)), "⇧⌘")
    }
}

/// Builds the full sample home folder and checks what Haven makes of it, end to end (minus the UI).
final class FixtureLibraryTests: XCTestCase {
    static var root: String = ""
    static var items: [FileItem] = []

    override class func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("haven-fixture-\(UUID().uuidString)").path
        FixtureFactory.make(at: root)
        var options = ScanOptions()
        options.honorTestDates = true
        items = IndexRoot.standard(home: root, applications: (root as NSString).appendingPathComponent("Applications"))
            .flatMap { FileScanner.scan(root: $0, options: options) }
    }

    override class func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
        super.tearDown()
    }

    var items: [FileItem] { Self.items }

    func names(_ text: String) -> Set<String> {
        Set(SearchEngine.search(QueryParser.parse(text).query, in: items).map(\.name))
    }

    func testIndexFindsEverything() {
        XCTAssertGreaterThan(items.count, 30)
        XCTAssertTrue(items.contains { $0.name == "Old Editor.app" && $0.kind == .app })
        XCTAssertEqual(items.filter(\.isScreenshot).count, 3)
    }

    func testPlainEnglishSearches() {
        XCTAssertEqual(names("pdfs from last week"), ["Q3-report.pdf"])
        XCTAssertEqual(names("from gmail"), ["Q3-report.pdf", "invoice-4821.png"])
        XCTAssertTrue(names("photos from whatsapp").contains("WhatsApp Image 2026-10-15.jpeg"))
        XCTAssertEqual(names("airdrop"), ["IMG_7781.jpeg"])
        XCTAssertEqual(names("installers"), ["Zoom-6.2.pkg", "Figma-124.dmg"])
        XCTAssertEqual(names("big videos older than a year"), ["Holiday 2023.mov"])
        XCTAssertEqual(names("#work"), ["Project Plan.pdf"])
        XCTAssertTrue(names("screenshots").contains("Screenshot 2026-10-12 at 09.41.22.png"))
        XCTAssertEqual(names("songs"), ["Morning Tune.wav", "Evening Tune.wav"])
    }

    func testCleanupCards() {
        let cards = Dictionary(uniqueKeysWithValues: CleanupEngine.cards(in: items).map { ($0.kind, Set($0.items.map(\.name))) })
        XCTAssertEqual(cards[.oldInstallers], ["Zoom-6.2.pkg", "Figma-124.dmg"])
        XCTAssertEqual(cards[.forgottenDownloads], ["bank-statement-march.pdf"])
        XCTAssertEqual(cards[.oldScreenshots], ["Screenshot 2026-08-02 at 18.10.05.png"])
        XCTAssertEqual(cards[.bigOldVideos], ["Holiday 2023.mov"])
        XCTAssertEqual(cards[.unusedApps], ["Old Editor.app"])
        XCTAssertEqual(cards[.unzippedArchives], ["holiday-photos.zip"])
    }

    func testDuplicatesAndLookAlikes() {
        var cache: [String: String] = [:]
        let identical = DuplicateFinder.identicalGroups(in: items, hashCache: &cache)
        let goa = identical.first { $0.items.contains { $0.name == "Goa Beach.jpg" } }
        XCTAssertEqual(goa?.items.count, 3)
        XCTAssertTrue(goa?.suggestedKeep.hasSuffix("Pictures/Trips/Goa Beach.jpg") ?? false)

        let photos = items.filter { $0.kind == .image && !$0.isScreenshot }
        let similar = SimilarPhotoFinder.groups(in: photos, threshold: DuplicateService.similarityThreshold)
        let pair = similar.first { g in g.items.contains { $0.name == "IMG_2041.jpg" } }
        XCTAssertEqual(Set(pair?.items.map(\.name) ?? []), ["IMG_2041.jpg", "IMG_2041.heic"])
    }

    func testSourcesSummary() {
        let d = LibraryDerived.compute(items, cleanup: CleanupSettings())
        let ids = Set(d.sources.map(\.source.id))
        XCTAssertTrue(ids.isSuperset(of: ["gmail", "canva", "chatgpt", "whatsapp", "airdrop", "github", "zoom", "figma"]), "\(ids)")
        XCTAssertEqual(d.sources.first?.source.id, "gmail")
        XCTAssertGreaterThan(d.stats[.images]?.count ?? 0, 10)
    }

    func testOCRMakesScreenshotsSearchable() {
        let shot = items.first { $0.name == "Screenshot 2026-10-12 at 09.41.22.png" }!
        let text = TextExtractor.extract(shot) ?? ""
        print("Boarding pass OCR:", text.replacingOccurrences(of: "\n", with: " | "))
        let store = TextStore()
        store.set(text, for: shot)
        let found = SearchEngine.search(QueryParser.parse("boarding pass").query, in: items, text: { store.folded(for: $0) })
        XCTAssertEqual(found.map(\.name), [shot.name])
    }
}
