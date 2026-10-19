import XCTest
@testable import HavenCore

final class SourceClassifierTests: XCTestCase {

    func id(_ froms: [String], agent: String? = nil) -> String? {
        SourceClassifier.classify(whereFroms: froms, quarantineAgent: agent)?.id
    }

    func testKnownServices() {
        XCTAssertEqual(id(["https://mail-attachment.googleusercontent.com/attachment/u/0/?ui=2&ik=1", "https://mail.google.com/"]), "gmail")
        XCTAssertEqual(id(["https://drive.usercontent.google.com/download?id=abc", "https://drive.google.com/"]), "gdrive")
        XCTAssertEqual(id(["https://files.oaiusercontent.com/file-abc?se=1", "https://chatgpt.com/c/123"]), "chatgpt")
        XCTAssertEqual(id(["blob:https://web.whatsapp.com/5d3e-11"]), "whatsapp")
        XCTAssertEqual(id(["https://pbs.twimg.com/media/abc.jpg", "https://x.com/someone/status/1"]), "x")
        XCTAssertEqual(id(["https://codeload.github.com/a/b/zip/refs/heads/main", "https://github.com/a/b"]), "github")
        XCTAssertEqual(id(["https://export-download.canva.com/x/design.png", "https://www.canva.com/design/1"]), "canva")
        XCTAssertEqual(id(["https://files.slack.com/files-pri/T1/download/a.pdf"]), "slack")
        XCTAssertEqual(id(["chrome-extension://abcdef/popup.html"]), "extension")
    }

    func testQuarantineAgents() {
        XCTAssertEqual(id([], agent: "sharingd"), "airdrop")
        XCTAssertEqual(id([], agent: "WhatsApp"), "whatsapp")
        XCTAssertEqual(id([], agent: "Mail"), "mail")
        XCTAssertNil(id([], agent: "Safari"))
        XCTAssertEqual(quarantineAgentName("0083;6512a3c1;Safari;6B29FC40-CA47-1067-B31D-00DD010662DA"), "Safari")
        XCTAssertNil(quarantineAgentName("0083;6512a3c1;;"))
    }

    func testUnknownWebsiteUsesPageDomain() {
        let s = SourceClassifier.classify(whereFroms: ["https://cdn.files.example.co.uk/x.pdf", "https://www.example.co.uk/page"], quarantineAgent: "Safari")
        XCTAssertEqual(s?.id, "site:example.co.uk")
        XCTAssertEqual(s?.name, "example.co.uk")
        XCTAssertEqual(s?.host, "example.co.uk")
        XCTAssertTrue(s?.isWebsite ?? false)
    }

    func testRegistrableDomain() {
        XCTAssertEqual(SourceClassifier.registrableDomain("a.b.example.com"), "example.com")
        XCTAssertEqual(SourceClassifier.registrableDomain("www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(SourceClassifier.registrableDomain("localhost"), "localhost")
    }

    func testMonogram() {
        XCTAssertEqual(SourceClassifier.source(withID: "gdrive")?.monogram, "GD")
        XCTAssertEqual(SourceClassifier.source(withID: "gmail")?.monogram, "G")
        XCTAssertEqual(SourceClassifier.source(withID: "x")?.monogram, "X")
        XCTAssertEqual(SourceClassifier.source(withID: "site:example.com")?.name, "example.com")
    }
}

final class SearchEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func item(_ name: String, daysAgo: Double = 1, size: Int64 = 1000, root: String = "documents", froms: [String] = [],
              screenshot: Bool = false, tags: [String] = [], folder: String = "/u/Documents") -> FileItem {
        let d = now.addingTimeInterval(-daysAgo * 86_400)
        return FileItem(path: folder + "/" + name, size: size, created: d, modified: d, added: d, rootID: root, tags: tags,
                        whereFroms: froms, isScreenshot: screenshot, isDirectory: !name.contains("."))
    }

    lazy var items: [FileItem] = [
        item("Tax Return 2024.pdf", daysAgo: 3),
        item("holiday.jpg", daysAgo: 40, size: 4_000_000, root: "pictures"),
        item("Screenshot 2026-10-01.png", daysAgo: 10, size: 6_000_000, root: "desktop", screenshot: true),
        item("Screenshot small.png", daysAgo: 2, size: 200_000, root: "desktop", screenshot: true),
        item("attachment.pdf", daysAgo: 1, root: "downloads", froms: ["https://mail.google.com/"], folder: "/u/Downloads"),
        item("budget.xlsx", daysAgo: 400, size: 50_000, tags: ["Work"]),
        item("Invoices", daysAgo: 5),
        item("notes.txt", daysAgo: 1, folder: "/u/Documents/Taxes"),
    ]

    func run(_ text: String, textLookup: SearchEngine.TextLookup? = nil) -> [String] {
        SearchEngine.search(QueryParser.parse(text).query, in: items, now: now, text: textLookup).map(\.name)
    }

    func testKindAndDate() {
        XCTAssertEqual(run("pdfs"), ["attachment.pdf", "Tax Return 2024.pdf"])
        XCTAssertEqual(run("pdfs past week"), ["attachment.pdf", "Tax Return 2024.pdf"])
        XCTAssertEqual(run("images older than a month"), ["holiday.jpg"])
    }

    func testScreenshotsBySize() {
        XCTAssertEqual(run("screenshots over 5 MB"), ["Screenshot 2026-10-01.png"])
        XCTAssertEqual(run("screenshots"), ["Screenshot small.png", "Screenshot 2026-10-01.png"])
    }

    func testSource() {
        XCTAssertEqual(run("from gmail"), ["attachment.pdf"])
        XCTAssertEqual(run("downloaded pdfs"), ["attachment.pdf"])
    }

    func testTermsMatchNameFolderTagsAndText() {
        XCTAssertEqual(run("tax"), ["Tax Return 2024.pdf", "notes.txt"])
        XCTAssertEqual(run("work"), ["budget.xlsx"])
        XCTAssertEqual(run("#work"), ["budget.xlsx"])
        let text: SearchEngine.TextLookup = { $0.hasSuffix("holiday.jpg") ? "sunset over goa beach" : nil }
        XCTAssertEqual(run("goa", textLookup: text), ["holiday.jpg"])
        XCTAssertEqual(run("beach images", textLookup: text), ["holiday.jpg"])
    }

    func testFoldersOnlyForNameSearches() {
        XCTAssertEqual(run("invoices"), ["Invoices"])
        XCTAssertFalse(run("from gmail").contains("Invoices"))
        XCTAssertEqual(run("folders"), ["Invoices"])
    }

    func testSortHint() {
        XCTAssertEqual(run("largest images").first, "Screenshot 2026-10-01.png")
        XCTAssertEqual(run("oldest").first, "budget.xlsx")
    }

    func testRootFilter() {
        XCTAssertEqual(Set(run("on desktop")), ["Screenshot 2026-10-01.png", "Screenshot small.png"])
    }

    func testRanking() {
        let more = items + [item("old tax notes.pdf", daysAgo: 1)]
        let names = SearchEngine.search(QueryParser.parse("tax").query, in: more, now: now).map(\.name)
        // A name that starts with the word beats one that merely contains it, which beats a folder match.
        XCTAssertEqual(names, ["Tax Return 2024.pdf", "old tax notes.pdf", "notes.txt"])
    }

    func testSortOrders() {
        let sorted = FileSortOrder.sizeLargest.sorted(items)
        XCTAssertEqual(sorted.first?.name, "Screenshot 2026-10-01.png")
        XCTAssertEqual(FileSortOrder.nameAZ.sorted(items).first?.name, "attachment.pdf")
    }
}
