import Foundation
@testable import HavenCore
import XCTest

final class CustomRuleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let downloads = "/Users/me/Downloads"

    func file(_ name: String, in dir: String? = nil, daysAgo: Double = 2, opened: Double? = nil, size: Int64 = 1000,
              froms: [String] = [], screenshot: Bool = false) -> FileItem {
        let d = now.addingTimeInterval(-daysAgo * 86_400)
        return FileItem(path: (dir ?? downloads) + "/" + name, size: size, created: d, modified: d, added: d,
                        lastOpened: opened.map { now.addingTimeInterval(-$0 * 86_400) }, whereFroms: froms, isScreenshot: screenshot)
    }

    let gmail = ["https://mail.google.com/mail/u/0/"]
    let whatsapp = ["blob:https://web.whatsapp.com/1"]

    func testInvoicesFromGmailMoveToTheirFolder() {
        let rule = CustomRule(name: "Invoices", folders: [downloads], conditions: [.source("gmail"), .textContains("Invoice")],
                              action: .move(to: "/Users/me/Documents/Invoices", byMonth: false))
        let items = [
            file("inv.pdf", froms: gmail),
            file("photo.jpg", froms: gmail),
            file("other.pdf", froms: whatsapp),
            file("deep.pdf", in: downloads + "/project", froms: gmail),
            file("fresh.pdf", daysAgo: 0, froms: gmail),
        ]
        let text: [String: String] = [
            items[0].path: "invoice #4821 total due",
            items[1].path: "invoice inside a photo",
            items[2].path: "invoice",
            items[3].path: "invoice",
            items[4].path: "invoice",
        ]
        let steps = CustomRulePlanner.plan(rule, items: items, text: { text[$0] }, now: now)
        XCTAssertEqual(steps.map(\.item.name), ["inv.pdf", "photo.jpg"], "only files right in Downloads, from Gmail, with the word")
        XCTAssertEqual(steps.first?.destination, "/Users/me/Documents/Invoices")
    }

    func testMonthFoldersAndFilesAlreadyThere() {
        let rule = CustomRule(name: "WhatsApp", folders: [downloads, "/Users/me/Pictures/WhatsApp"],
                              conditions: [.source("whatsapp"), .kind(.image)],
                              action: .move(to: "/Users/me/Pictures/WhatsApp", byMonth: false))
        let here = file("a.jpg", in: "/Users/me/Pictures/WhatsApp", froms: whatsapp)
        let new = file("b.jpg", froms: whatsapp)
        XCTAssertEqual(CustomRulePlanner.plan(rule, items: [here, new], now: now).map(\.item.name), ["b.jpg"],
                       "a file already in the destination stays put")
        var monthly = rule
        monthly.action = .move(to: "/Users/me/Pictures/WhatsApp", byMonth: true)
        let cal = Calendar(identifier: .gregorian)
        let step = CustomRulePlanner.plan(monthly, items: [new], now: now, calendar: cal).first
        XCTAssertEqual(step?.destination, "/Users/me/Pictures/WhatsApp/" + RulesPlanner.monthFolderName(for: new.arrivalDate, calendar: cal))
    }

    func testEveryKindOfCondition() {
        let old = file("Report FINAL.PDF", daysAgo: 200, opened: 150, size: 300 * ByteSize.mb)
        func ok(_ c: RuleCondition) -> Bool { CustomRulePlanner.matches(old, [c], text: nil, now: now) }
        XCTAssertTrue(ok(.kind(.pdf)))
        XCTAssertTrue(ok(.nameContains("final")))
        XCTAssertFalse(ok(.nameContains("draft")))
        XCTAssertTrue(ok(.extensionIs(".pdf")))
        XCTAssertTrue(ok(.olderThan(days: 100)))
        XCTAssertFalse(ok(.olderThan(days: 300)))
        XCTAssertTrue(ok(.notOpenedFor(days: 100)))
        XCTAssertFalse(ok(.notOpenedFor(days: 160)))
        XCTAssertTrue(ok(.biggerThan(megabytes: 200)))
        XCTAssertFalse(ok(.source("*")), "not downloaded")
        XCTAssertFalse(ok(.textContains("x")), "no text read")
        XCTAssertFalse(ok(.isScreenshot))
        XCTAssertFalse(ok(.nameContains("  ")), "an empty word never matches")
    }

    func testHalfMadeAndUnsafeRulesDoNothing() {
        let items = [file("a.pdf"), file("b.zip")]
        let trashAll = CustomRule(name: "x", folders: [downloads], conditions: [], action: .trash)
        XCTAssertTrue(CustomRulePlanner.plan(trashAll, items: items, now: now).isEmpty, "a trash rule needs at least one condition")
        let noFolder = CustomRule(name: "x", folders: [], conditions: [.kind(.pdf)], action: .trash)
        XCTAssertTrue(CustomRulePlanner.plan(noFolder, items: items, now: now).isEmpty)
        let partial = file("movie.mp4.crdownload")
        let rule = CustomRule(name: "x", folders: [downloads], conditions: [.olderThan(days: 1)], action: .trash)
        XCTAssertEqual(CustomRulePlanner.plan(rule, items: items + [partial], now: now).count, 2, "downloads in progress are left alone")
    }

    func testRulesSurviveSaving() throws {
        let rules = CustomRulePlanner.suggestions(home: "/Users/me") + [
            CustomRule(name: "c", folders: ["/x"], conditions: [.biggerThan(megabytes: 5), .extensionIs("zip")],
                       action: .addToCollection(UUID())),
        ]
        let back = try JSONDecoder().decode([CustomRule].self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(back, rules)
    }

    func testDescriptionsReadLikeSentences() {
        let rule = CustomRulePlanner.suggestions(home: "/Users/me")[0]
        XCTAssertEqual(CustomRulePlanner.describe(rule, home: "/Users/me"),
                       "Any file in Downloads that comes from Gmail and has “invoice” in its text: move to ~/Documents/Invoices.")
        let trash = CustomRulePlanner.suggestions(home: "/Users/me")[3]
        XCTAssertEqual(CustomRulePlanner.describe(trash, home: "/Users/me"),
                       "Any file in Downloads that arrived over 180 days ago and wasn't opened for 180 days: move to the Trash.")
    }

    func testPlanningAgainstALargeIndexIsQuick() {
        let items = SyntheticLibrary.make(count: 100_000)
        let rule = CustomRule(name: "x", folders: ["/Users/me/Downloads"], conditions: [.source("*"), .olderThan(days: 30)], action: .trash)
        let start = Date()
        _ = CustomRulePlanner.plan(rule, items: items, now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
