import XCTest
@testable import HavenCore

final class QueryParserTests: XCTestCase {

    func labels(_ text: String) -> [String] {
        QueryParser.parse(text).chips.map(\.label)
    }

    func testPDFsFromLastWeek() {
        let p = QueryParser.parse("pdfs from last week")
        XCTAssertEqual(p.query.kinds, [.pdf])
        XCTAssertEqual(p.query.date, .lastWeek)
        XCTAssertTrue(p.query.terms.isEmpty)
        XCTAssertEqual(p.chips.map(\.label), ["PDFs", "Last week"])
    }

    func testScreenshotsOverFiveMB() {
        let p = QueryParser.parse("screenshots over 5 MB")
        XCTAssertTrue(p.query.screenshots)
        XCTAssertEqual(p.query.minSize, 5 * ByteSize.mb)
        XCTAssertEqual(p.chips.map(\.label), ["Screenshots", "Over 5 MB"])
    }

    func testGluedSizeAndComparators() {
        XCTAssertEqual(QueryParser.parse("videos bigger than 1.5gb").query.minSize, 1_500_000_000)
        XCTAssertEqual(QueryParser.parse("images under 100kb").query.maxSize, 100 * ByteSize.kb)
        XCTAssertEqual(QueryParser.parse("at least 20 mb").query.minSize, 20 * ByteSize.mb)
        let between = QueryParser.parse("between 5 and 10 mb").query
        XCTAssertEqual(between.minSize, 5 * ByteSize.mb)
        XCTAssertEqual(between.maxSize, 10 * ByteSize.mb)
        XCTAssertEqual(QueryParser.parse("movies 2gb").query.minSize, 2 * ByteSize.gb)
    }

    func testPhotosFromWhatsApp() {
        let p = QueryParser.parse("photos from whatsapp")
        XCTAssertEqual(p.query.kinds, [.image])
        XCTAssertEqual(p.query.sourceIDs, ["whatsapp"])
        XCTAssertEqual(p.chips.map(\.label), ["Images", "From WhatsApp"])
    }

    func testBareBrandIsSource() {
        XCTAssertEqual(QueryParser.parse("chatgpt images").query.sourceIDs, ["chatgpt"])
        // Ordinary words need "from" to become a source.
        XCTAssertEqual(QueryParser.parse("apple invoice").query.terms, ["apple", "invoice"])
        XCTAssertEqual(QueryParser.parse("receipt from apple").query.sourceIDs, ["apple"])
    }

    func testWebsiteSource() {
        let p = QueryParser.parse("pdfs from example.com")
        XCTAssertEqual(p.query.sourceIDs, ["site:example.com"])
    }

    func testBigOldVideos() {
        let q = QueryParser.parse("big videos older than a year").query
        XCTAssertEqual(q.kinds, [.video])
        XCTAssertEqual(q.minSize, 100 * ByteSize.mb)
        XCTAssertEqual(q.date, .olderThan(1, .year))
    }

    func testOldScreenshots() {
        let q = QueryParser.parse("old screenshots").query
        XCTAssertTrue(q.screenshots)
        XCTAssertEqual(q.date, .olderThan(6, .month))
    }

    func testBareYearIsText() {
        let q = QueryParser.parse("invoice 2024").query
        XCTAssertEqual(q.terms, ["invoice", "2024"])
        XCTAssertNil(q.date)
    }

    func testYearWithPreposition() {
        let q = QueryParser.parse("tax documents in 2024").query
        XCTAssertEqual(q.terms, ["tax"])
        XCTAssertEqual(q.date, .year(2024))
        XCTAssertTrue(q.kinds.contains(.pdf))
        XCTAssertTrue(q.kinds.contains(.spreadsheet))
    }

    func testDownloadedYesterday() {
        let p = QueryParser.parse("downloaded yesterday")
        XCTAssertEqual(p.query.date, .yesterday)
        XCTAssertEqual(p.query.dateField, .added)
        XCTAssertEqual(p.chips.map(\.label), ["Downloaded yesterday"])
        XCTAssertEqual(p.chips.first?.tokenIndexes.sorted(), [0, 1])
    }

    func testDownloadedFromGmail() {
        let p = QueryParser.parse("downloaded from gmail")
        XCTAssertEqual(p.query.sourceIDs, ["gmail"])
        XCTAssertFalse(p.query.downloadedOnly)
        XCTAssertEqual(p.chips.map(\.label), ["From Gmail"])
        XCTAssertEqual(p.text(removing: p.chips[0]), "")
    }

    func testDownloadedAlone() {
        let p = QueryParser.parse("downloaded pdfs")
        XCTAssertTrue(p.query.downloadedOnly)
        XCTAssertEqual(p.chips.map(\.label), ["PDFs", "Downloaded"])
    }

    func testLatestDownloads() {
        let q = QueryParser.parse("latest downloads").query
        XCTAssertEqual(q.sort, .newest)
        XCTAssertEqual(q.rootIDs, ["downloads"])
    }

    func testLocationsNeedPrepositionWhenAmbiguous() {
        XCTAssertEqual(QueryParser.parse("music").query.kinds, [.audio])
        XCTAssertEqual(QueryParser.parse("music").query.rootIDs, [])
        XCTAssertEqual(QueryParser.parse("songs in music").query.rootIDs, ["music"])
        XCTAssertEqual(QueryParser.parse("on my desktop").query.rootIDs, ["desktop"])
        XCTAssertEqual(QueryParser.parse("desktop").query.rootIDs, ["desktop"])
        XCTAssertEqual(QueryParser.parse("documents folder").query.rootIDs, ["documents"])
        XCTAssertEqual(QueryParser.parse("from downloads").query.rootIDs, ["downloads"])
    }

    func testCustomRoot() {
        let q = QueryParser.parse("pdfs in projects", customRoots: ["projects": "custom:/Users/me/Projects"]).query
        XCTAssertEqual(q.rootIDs, ["custom:/Users/me/Projects"])
    }

    func testTagsAndExtensions() {
        let q = QueryParser.parse("#work .psd pngs").query
        XCTAssertEqual(q.tags, ["work"])
        XCTAssertEqual(q.extensions, ["psd", "png"])
        XCTAssertEqual(QueryParser.parse("jpg").query.extensions, ["jpg", "jpeg"])
        XCTAssertEqual(QueryParser.parse("tagged red").query.tags, ["red"])
    }

    func testQuotedPhrase() {
        let p = QueryParser.parse("\"quarterly report\" since march")
        XCTAssertEqual(p.query.terms, ["quarterly report"])
        XCTAssertEqual(p.query.date, .since(.month(3, year: nil)))
        XCTAssertEqual(p.chips.map(\.label), ["Since March", "“quarterly report”"])
    }

    func testRelativeDates() {
        XCTAssertEqual(QueryParser.parse("last 3 days").query.date, .within(3, .day))
        XCTAssertEqual(QueryParser.parse("in the past 2 weeks").query.date, .within(2, .week))
        XCTAssertEqual(QueryParser.parse("2 weeks ago").query.date, .ago(2, .week))
        XCTAssertEqual(QueryParser.parse("past month").query.date, .within(1, .month))
        XCTAssertEqual(QueryParser.parse("last month").query.date, .lastMonth)
        XCTAssertEqual(QueryParser.parse("this year").query.date, .thisYear)
        XCTAssertEqual(QueryParser.parse("today").query.date, .today)
        XCTAssertEqual(QueryParser.parse("within a week").query.date, .within(1, .week))
        XCTAssertEqual(QueryParser.parse("before 2020").query.date, .before(.year(2020)))
        XCTAssertEqual(QueryParser.parse("march 2024").query.date, .month(3, year: 2024))
        XCTAssertEqual(QueryParser.parse("on monday").query.date, .weekday(2))
        XCTAssertEqual(QueryParser.parse("recent screenshots").query.date, .within(30, .day))
        XCTAssertEqual(QueryParser.parse("more than 6 months old").query.date, .olderThan(6, .month))
    }

    func testMayIsOnlyAMonthInContext() {
        XCTAssertEqual(QueryParser.parse("may").query.terms, ["may"])
        XCTAssertEqual(QueryParser.parse("in may").query.date, .month(5, year: nil))
        XCTAssertEqual(QueryParser.parse("mar").query.terms, ["mar"])
    }

    func testScreenRecordings() {
        let q = QueryParser.parse("screen recordings this month").query
        XCTAssertTrue(q.screenRecordings)
        XCTAssertFalse(q.screenshots)
        XCTAssertEqual(q.date, .thisMonth)
    }

    func testSortHints() {
        XCTAssertEqual(QueryParser.parse("largest videos").query.sort, .largest)
        XCTAssertEqual(QueryParser.parse("oldest pdfs").query.sort, .oldest)
        XCTAssertEqual(QueryParser.parse("most recent photos").query.sort, .newest)
    }

    func testStopwordsAreIgnored() {
        let q = QueryParser.parse("show me all the files about taxes").query
        XCTAssertEqual(q.terms, ["taxes"])
    }

    func testRemovingChipEditsText() {
        let p = QueryParser.parse("pdfs from last week")
        let date = p.chips.first { $0.kind == .date }!
        XCTAssertEqual(p.text(removing: date), "pdfs")
        let type = p.chips.first { $0.kind == .type }!
        XCTAssertEqual(p.text(removing: type), "from last week")
    }

    func testCombinedQuery() {
        let p = QueryParser.parse("photos from whatsapp last month bigger than 2mb")
        XCTAssertEqual(p.query.kinds, [.image])
        XCTAssertEqual(p.query.sourceIDs, ["whatsapp"])
        XCTAssertEqual(p.query.date, .lastMonth)
        XCTAssertEqual(p.query.minSize, 2 * ByteSize.mb)
        XCTAssertTrue(p.query.terms.isEmpty)
    }

    func testHeadline() {
        XCTAssertEqual(QueryParser.parse("pdfs from last week").headline, "PDFs · Last week")
        XCTAssertEqual(QueryParser.parse("largest photos from whatsapp").headline, "Images · From WhatsApp")
        XCTAssertEqual(QueryParser.parse("the").headline, "the")
    }

    func testEmpty() {
        XCTAssertTrue(QueryParser.parse("").query.isEmpty)
        XCTAssertTrue(QueryParser.parse("   ").chips.isEmpty)
        XCTAssertTrue(QueryParser.parse("the files").query.isEmpty)
    }

    func testAccentsFold() {
        XCTAssertEqual(QueryParser.parse("Résumé").query.terms, ["resume"])
    }
}

final class DateSpecTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // Monday 19 Oct 2026, noon.
    var now: Date { date(2026, 10, 19, 12) }

    func testLastWeek() {
        let r = DateSpec.lastWeek.resolve(now: now, calendar: cal)
        XCTAssertEqual(r.start, date(2026, 10, 12))
        XCTAssertEqual(r.end, date(2026, 10, 19))
    }

    func testMonthWithoutYearPicksMostRecent() {
        XCTAssertEqual(DateSpec.month(3, year: nil).resolve(now: now, calendar: cal).start, date(2026, 3, 1))
        XCTAssertEqual(DateSpec.month(11, year: nil).resolve(now: now, calendar: cal).start, date(2025, 11, 1))
    }

    func testWithinAndOlder() {
        XCTAssertEqual(DateSpec.within(3, .day).resolve(now: now, calendar: cal).start, date(2026, 10, 16, 12))
        let older = DateSpec.olderThan(1, .year).resolve(now: now, calendar: cal)
        XCTAssertNil(older.start)
        XCTAssertEqual(older.end, date(2025, 10, 19, 12))
    }

    func testWeekdayAndYesterday() {
        XCTAssertEqual(DateSpec.weekday(2).resolve(now: now, calendar: cal).start, date(2026, 10, 19))
        XCTAssertEqual(DateSpec.weekday(6).resolve(now: now, calendar: cal).start, date(2026, 10, 16))
        XCTAssertEqual(DateSpec.yesterday.resolve(now: now, calendar: cal).start, date(2026, 10, 18))
    }

    func testSinceBeforeAfter() {
        XCTAssertEqual(DateSpec.since(.year(2024)).resolve(now: now, calendar: cal).start, date(2024, 1, 1))
        XCTAssertEqual(DateSpec.before(.year(2024)).resolve(now: now, calendar: cal).end, date(2024, 1, 1))
        XCTAssertEqual(DateSpec.after(.year(2024)).resolve(now: now, calendar: cal).start, date(2025, 1, 1))
    }

    func testLabels() {
        XCTAssertEqual(DateSpec.within(3, .month).label, "Past 3 months")
        XCTAssertEqual(DateSpec.within(1, .week).label, "Past week")
        XCTAssertEqual(DateSpec.since(.lastWeek).label, "Since last week")
        XCTAssertEqual(DateSpec.since(.month(3, year: nil)).label, "Since March")
    }
}
