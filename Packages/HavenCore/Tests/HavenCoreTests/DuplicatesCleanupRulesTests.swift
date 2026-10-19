import XCTest
@testable import HavenCore

final class HashingTests: XCTestCase {
    func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testKnownVectors() throws {
        XCTAssertEqual(FileHasher.sha256(of: try write(Data("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(FileHasher.sha256(of: try write(Data())),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        XCTAssertEqual(FileHasher.sha256(of: try write(million)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

final class DuplicateFinderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-dupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func file(_ rel: String, _ data: Data, root: String) throws -> FileItem {
        let url = dir.appendingPathComponent(rel)
        try data.write(to: url)
        let now = Date()
        return FileItem(path: url.path, size: Int64(data.count), created: now, modified: now, rootID: root)
    }

    func testFindsIdenticalFilesAndKeepsTheOriginal() throws {
        let big = Data((0..<200_000).map { UInt8($0 % 251) })
        var sameSizeDifferent = big
        sameSizeDifferent[150_000] ^= 0xFF
        let items = [
            try file("Documents/report.pdf", big, root: "documents"),
            try file("Downloads/report (1).pdf", big, root: "downloads"),
            try file("Downloads/report copy.pdf", big, root: "downloads"),
            try file("Downloads/other.pdf", sameSizeDifferent, root: "downloads"),
            try file("Documents/small.txt", Data("hello".utf8), root: "documents"),
            try file("Downloads/small.txt", Data("hello".utf8), root: "downloads"),
            try file("Documents/unique.txt", Data("unique".utf8), root: "documents"),
        ]
        var cache: [String: String] = [:]
        let groups = DuplicateFinder.identicalGroups(in: items, hashCache: &cache)
        XCTAssertEqual(groups.count, 2)
        let reports = groups.first { $0.items.count == 3 }!
        XCTAssertTrue(reports.suggestedKeep.hasSuffix("Documents/report.pdf"))
        XCTAssertEqual(reports.items.first?.path, reports.suggestedKeep)
        XCTAssertEqual(reports.reclaimableBytes, 400_000)
        let small = groups.first { $0.items.count == 2 }!
        XCTAssertTrue(small.suggestedKeep.hasSuffix("Documents/small.txt"))
        XCTAssertFalse(cache.isEmpty)
        // Head hashes of every same-size file are remembered, so the next run reads nothing that hasn't changed.
        XCTAssertEqual(cache.keys.filter { $0.hasPrefix("head|") }.count, 6)
        // Cached hashes are reused.
        let again = DuplicateFinder.identicalGroups(in: items, hashCache: &cache)
        XCTAssertEqual(again.map(\.id).sorted(), groups.map(\.id).sorted())
    }

    func testTrashingDuplicatesAlwaysLeavesACopy() {
        let d = Date()
        let a = FileItem(path: "/x/a.jpg", size: 10, created: d, modified: d)
        let b = FileItem(path: "/x/b.jpg", size: 10, created: d, modified: d)
        let c = FileItem(path: "/x/c.jpg", size: 10, created: d, modified: d)
        let group = DuplicateGroup(id: "g", kind: .identical, items: [a, b, c], suggestedKeep: a.path)
        // The user marked every copy Trash: Haven's pick stays.
        let all = DuplicateFinder.safeToTrash(groups: [group], keeps: { _, _ in false }, unchanged: { _ in true })
        XCTAssertEqual(Set(all.map(\.path)), [b.path, c.path])
        // The kept copy changed or vanished since the check: nothing in the group is touched.
        let keeperGone = DuplicateFinder.safeToTrash(groups: [group], keeps: { i, g in i.path == g.suggestedKeep },
                                                     unchanged: { $0.path != a.path })
        XCTAssertTrue(keeperGone.isEmpty)
        // A copy edited since the check stays.
        let edited = DuplicateFinder.safeToTrash(groups: [group], keeps: { i, g in i.path == g.suggestedKeep },
                                                 unchanged: { $0.path != c.path })
        XCTAssertEqual(edited.map(\.path), [b.path])
    }

    func testUnchangedChecksTheDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("haven-unchanged-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attrs[.modificationDate] as! Date
        let item = FileItem(path: url.path, size: 5, created: modified, modified: modified)
        XCTAssertTrue(DuplicateFinder.isUnchanged(item))
        try Data("hello, changed".utf8).write(to: url)
        XCTAssertFalse(DuplicateFinder.isUnchanged(item))
        XCTAssertFalse(DuplicateFinder.isUnchanged(FileItem(path: url.path + ".gone", size: 5, created: modified, modified: modified)))
    }

    func testCloudOnlyFilesAreSkipped() throws {
        let data = Data("same".utf8)
        let a = try file("Documents/a.txt", data, root: "documents")
        let bURL = dir.appendingPathComponent("Documents/b.txt")
        try data.write(to: bURL)
        let b = FileItem(path: bURL.path, size: 4, created: Date(), modified: Date(), rootID: "documents", isCloudOnly: true)
        var cache: [String: String] = [:]
        XCTAssertTrue(DuplicateFinder.identicalGroups(in: [a, b], hashCache: &cache).isEmpty)
    }

    func testLooksLikeCopy() {
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("report copy"))
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("report (2)"))
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("report-1"))
        XCTAssertFalse(DuplicateFinder.looksLikeCopy("img_1234"))
        XCTAssertFalse(DuplicateFinder.looksLikeCopy("report"))
    }

    func testSimilarKeeperPrefersMorePixels() {
        let d = Date()
        let a = FileItem(path: "/p/IMG_1.jpg", size: 900, created: d, modified: d)
        let b = FileItem(path: "/p/IMG_1.heic", size: 500, created: d, modified: d)
        XCTAssertEqual(DuplicateFinder.suggestKeeper([a, b], kind: .similar, pixels: [a.path: 100, b.path: 400]).path, b.path)
        XCTAssertEqual(DuplicateFinder.suggestKeeper([a, b], kind: .similar).path, a.path)
    }
}

final class SimilarityClustererTests: XCTestCase {
    func img(_ name: String, _ t: TimeInterval) -> FileItem {
        let d = Date(timeIntervalSince1970: 1_700_000_000 + t)
        return FileItem(path: "/Photos/" + name, created: d, modified: d)
    }

    func testStems() {
        XCTAssertEqual(SimilarityClusterer.stem(img("IMG_1234.HEIC", 0)), "img_1234")
        XCTAssertEqual(SimilarityClusterer.stem(img("IMG_E1234.jpg", 0)), "img_1234")
        XCTAssertEqual(SimilarityClusterer.stem(img("IMG_1234 (1).jpg", 0)), "img_1234")
        XCTAssertEqual(SimilarityClusterer.stem(img("beach copy.png", 0)), "beach")
    }

    func testCandidatePairsAndClusters() {
        let images = [
            img("IMG_1.HEIC", 0),        // 0
            img("IMG_1.JPG", 5_000),     // 1: same stem, different time
            img("burst_a.jpg", 10_000),  // 2
            img("burst_b.jpg", 10_030),  // 3: within window of 2
            img("far.jpg", 50_000),      // 4
        ]
        let pairs = SimilarityClusterer.candidatePairs(images, window: 120)
        XCTAssertTrue(pairs.contains { $0 == (0, 1) })
        XCTAssertTrue(pairs.contains { $0 == (2, 3) })
        XCTAssertFalse(pairs.contains { $0.0 == 4 || $0.1 == 4 })
        let distances: [String: Float] = ["0-1": 0.1, "2-3": 0.9]
        let clusters = SimilarityClusterer.clusters(count: images.count, pairs: pairs, threshold: 0.5) { a, b in
            distances["\(a)-\(b)"] ?? 99
        }
        XCTAssertEqual(clusters, [[0, 1]])
    }
}

final class CleanupEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func item(_ path: String, days: Double, size: Int64 = 10, root: String, screenshot: Bool = false, opened: Double? = nil, dir: Bool = false) -> FileItem {
        let d = now.addingTimeInterval(-days * 86_400)
        return FileItem(path: path, size: size, created: d, modified: d, added: d,
                        lastOpened: opened.map { now.addingTimeInterval(-$0 * 86_400) }, rootID: root,
                        isScreenshot: screenshot, isDirectory: dir)
    }

    func testCards() {
        let items = [
            item("/u/Downloads/Zoom.pkg", days: 60, size: 50_000_000, root: "downloads"),
            item("/u/Downloads/new-installer.dmg", days: 2, root: "downloads"),
            item("/u/Downloads/old.pdf", days: 200, root: "downloads"),
            item("/u/Downloads/old-but-opened.pdf", days: 200, root: "downloads", opened: 3),
            item("/u/Downloads/Sub/nested.pdf", days: 200, root: "downloads"),
            item("/u/Desktop/Screenshot 1.png", days: 45, root: "desktop", screenshot: true),
            item("/u/Desktop/Screenshot 2.png", days: 3, root: "desktop", screenshot: true),
            item("/u/Movies/trip.mov", days: 400, size: 900_000_000, root: "movies"),
            item("/u/Movies/clip.mov", days: 400, size: 9_000_000, root: "movies"),
            item("/Applications/Old.app", days: 500, root: "applications", opened: 200),
            item("/Applications/Daily.app", days: 500, root: "applications", opened: 1),
            item("/u/Downloads/photos.zip", days: 10, size: 5_000, root: "downloads"),
            item("/u/Downloads/photos", days: 10, root: "downloads", dir: true),
            item("/u/Downloads/lonely.zip", days: 10, root: "downloads"),
        ]
        let cards = Dictionary(uniqueKeysWithValues: CleanupEngine.cards(in: items, now: now).map { ($0.kind, $0.items.map(\.name)) })
        XCTAssertEqual(cards[.oldInstallers], ["Zoom.pkg"])
        XCTAssertEqual(cards[.forgottenDownloads], ["old.pdf"])
        XCTAssertEqual(cards[.oldScreenshots], ["Screenshot 1.png"])
        XCTAssertEqual(cards[.bigOldVideos], ["trip.mov"])
        XCTAssertEqual(cards[.unusedApps], ["Old.app"])
        XCTAssertEqual(cards[.unzippedArchives], ["photos.zip"])
        XCTAssertNil(cards[.duplicates])
    }
}

final class RulesPlannerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let now = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-15

    func testMonthFolderName() {
        let d = cal.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        XCTAssertEqual(RulesPlanner.monthFolderName(for: d, calendar: cal), "2026-03 March")
    }

    func testPlans() {
        let old = now.addingTimeInterval(-90 * 86_400)
        let fresh = now.addingTimeInterval(-3600)
        let items = [
            FileItem(path: "/u/Desktop/Screenshot old.png", created: old, modified: old, rootID: "desktop", isScreenshot: true),
            FileItem(path: "/u/Desktop/Screenshot new.png", created: fresh, modified: fresh, rootID: "desktop", isScreenshot: true),
            FileItem(path: "/u/Desktop/Folder/Screenshot nested.png", created: old, modified: old, rootID: "desktop", isScreenshot: true),
            FileItem(path: "/u/Downloads/app.dmg", created: old, modified: old, added: old, rootID: "downloads",
                     quarantineAgent: "Safari"),
            // Made on this Mac (no download mark): an automatic rule must never trash it.
            FileItem(path: "/u/Downloads/Vault.dmg", created: old, modified: old, added: old, rootID: "downloads"),
            FileItem(path: "/u/Downloads/linux.iso", created: old, modified: old, added: old, rootID: "downloads",
                     quarantineAgent: "Safari"),
            FileItem(path: "/u/Documents/Old/tool.pkg", created: old, modified: old, added: old, rootID: "documents",
                     quarantineAgent: "Safari"),
            FileItem(path: "/u/Downloads/paper.pdf", created: old, modified: old, added: old, rootID: "downloads"),
            FileItem(path: "/u/Downloads/today.pdf", created: fresh, modified: fresh, added: fresh, rootID: "downloads"),
        ]
        var settings = RuleSettings(home: "/u")
        settings.installerDays = 30
        let shots = RulesPlanner.plan(.fileScreenshots, items: items, settings: settings, screenshotSources: ["/u/Desktop"],
                                      downloadsFolder: "/u/Downloads", now: now, calendar: cal)
        XCTAssertEqual(shots.map(\.item.name), ["Screenshot old.png"])
        XCTAssertEqual(shots.first?.operation, .move(toDirectory: "/u/Pictures/Screenshots/2026-07 July"))

        let installers = RulesPlanner.plan(.trashOldInstallers, items: items, settings: settings, screenshotSources: [],
                                           downloadsFolder: "/u/Downloads", now: now, calendar: cal)
        XCTAssertEqual(installers.map(\.item.name), ["app.dmg"])
        XCTAssertEqual(installers.first?.operation, .trash)

        let archive = RulesPlanner.plan(.archiveOldDownloads, items: items, settings: settings, screenshotSources: [],
                                        downloadsFolder: "/u/Downloads", now: now, calendar: cal)
        XCTAssertEqual(Set(archive.map(\.item.name)), ["app.dmg", "Vault.dmg", "linux.iso", "paper.pdf"])
    }

    func testUniqueDestination() {
        let taken: Set<String> = ["/d/a.png", "/d/a 2.png"]
        XCTAssertEqual(RulesPlanner.uniqueDestination(name: "a.png", in: "/d", exists: taken.contains), "/d/a 3.png")
        XCTAssertEqual(RulesPlanner.uniqueDestination(name: "b.png", in: "/d", exists: taken.contains), "/d/b.png")
        XCTAssertEqual(RulesPlanner.uniqueDestination(name: "a.png", in: "/e", exists: { $0 == "/e/a.png" }), "/e/a 2.png")
    }

    func testTildePath() {
        XCTAssertEqual(tildePath("/u/Pictures/Screenshots", home: "/u"), "~/Pictures/Screenshots")
        XCTAssertEqual(tildePath("/other", home: "/u"), "/other")
    }
}

final class ScannerAndFormatTests: XCTestCase {
    func testScanSkipsNoiseAndClassifies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("haven-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("node_modules/pkg/index.js"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Photos/beach.jpg"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Screenshot 2026-01-01 at 10.00.00.png"))
        try Data("x".utf8).write(to: root.appendingPathComponent(".hidden"))
        try Data("abc".utf8).write(to: root.appendingPathComponent("notes.md"))
        let items = FileScanner.scan(root: IndexRoot(id: "test", path: root.path, name: "Test"))
        let names = Set(items.map(\.name))
        XCTAssertEqual(names, ["Photos", "beach.jpg", "Screenshot 2026-01-01 at 10.00.00.png", "notes.md"])
        XCTAssertEqual(items.first { $0.name == "Photos" }?.kind, .folder)
        XCTAssertEqual(items.first { $0.name == "beach.jpg" }?.kind, .image)
        XCTAssertEqual(items.first { $0.name == "notes.md" }?.size, 3)
        XCTAssertTrue(items.first { $0.name.hasPrefix("Screenshot") }!.isScreenshot)
        XCTAssertTrue(items.allSatisfy { $0.rootID == "test" })

        let listing = FileScanner.list(directory: root.path, rootID: "test")
        // Live updates list folders the same way the full scan does: no node_modules.
        XCTAssertEqual(Set(listing.map(\.name)), ["Photos", "Screenshot 2026-01-01 at 10.00.00.png", "notes.md"])
    }

    func testStandardRoots() {
        let roots = IndexRoot.standard(home: "/u")
        XCTAssertEqual(roots.map(\.id), ["desktop", "documents", "downloads", "pictures", "movies", "music", "applications"])
        XCTAssertEqual(roots.filter(\.isProtected).map(\.id), ["desktop", "documents", "downloads"])
    }

    func testByteFormatting() {
        XCTAssertEqual(ByteSize.format(5_000_000), "5 MB")
        XCTAssertEqual(ByteSize.format(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteSize.format(999), "999 bytes")
        XCTAssertEqual(ByteSize.format(14_130_000_000), "14.1 GB")
        XCTAssertEqual(ByteSize.format(250_000_000), "250 MB")
    }

    func testAgo() {
        let now = Date()
        XCTAssertEqual(HavenFormat.ago(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(HavenFormat.ago(now.addingTimeInterval(-3 * 86_400), now: now), "3 days ago")
        XCTAssertEqual(HavenFormat.ago(now.addingTimeInterval(-400 * 86_400), now: now), "a year ago")
        XCTAssertEqual(HavenFormat.duration(125), "2:05")
        XCTAssertEqual(HavenFormat.duration(3725), "1:02:05")
    }

    func testKindClassifier() {
        XCTAssertEqual(KindClassifier.kind(forExtension: "HEIC"), .image)
        XCTAssertEqual(KindClassifier.kind(forExtension: "dmg"), .installer)
        XCTAssertEqual(KindClassifier.kind(forExtension: "app", isDirectory: true, isPackage: true), .app)
        XCTAssertEqual(KindClassifier.kind(forExtension: "", isDirectory: true), .folder)
        XCTAssertEqual(KindClassifier.kind(forExtension: "key", isDirectory: true, isPackage: true), .presentation)
        XCTAssertEqual(FileKind.pdf.category, .documents)
        XCTAssertEqual(LibraryCategory.archives.kinds, [.archive, .installer])
    }

    func testActivitySummary() {
        let e = ActivityEntry(action: .trashed, reason: "Clean Up", moves: [.init(from: "/a/b.png", to: "/t/b.png", size: 5)])
        XCTAssertEqual(e.summary, "Moved b.png to the Trash")
        XCTAssertEqual(e.totalBytes, 5)
        XCTAssertEqual(SavedSearch.defaultName(for: " screenshots over 5 mb"), "Screenshots over 5 mb")
    }
}
