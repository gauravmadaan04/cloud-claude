import Foundation
@testable import HavenCore
import XCTest

final class RenamePlannerTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let oct12 = Date(timeIntervalSince1970: 1_760_270_400) // 2025-10-12 12:00 UTC

    func item(_ path: String, kind: FileKind? = nil, created: Date? = nil, source: DownloadSource?? = nil) -> FileItem {
        FileItem(path: path, kind: kind, created: created ?? oct12, modified: created ?? oct12, source: source)
    }

    func names(_ changes: [RenameChange]) -> [String] { changes.map(\.newName) }

    func plan(_ items: [FileItem], _ t: RenameTemplate, existing: [String: [String]] = [:],
              text: [String: String] = [:]) -> [RenameChange] {
        let ctx = RenameContext(text: { text[$0.path] }, timeZone: utc)
        return RenamePlanner.plan(items, template: t, context: ctx) { dir in
            existing[dir] ?? []
        }
    }

    func testTokensAndExtensionsStay() {
        let gmail = SourceClassifier.source(withID: "gmail")
        let files = [item("/d/IMG_0001.HEIC"), item("/d/report.final.pdf", source: .some(gmail))]
        XCTAssertEqual(names(plan(files, RenameTemplate(pattern: "{date} {name}"))),
                       ["2025-10-12 IMG_0001.HEIC", "2025-10-12 report.final.pdf"], "the extension keeps its spelling")
        XCTAssertEqual(names(plan(files, RenameTemplate(pattern: "Trip {n:3}", counterStart: 7))),
                       ["Trip 007.HEIC", "Trip 008.pdf"])
        XCTAssertEqual(names(plan(files, RenameTemplate(pattern: "{name} – {source}"))),
                       ["IMG_0001.HEIC", "report.final – Gmail.pdf"], "an empty token takes its separator with it")
        XCTAssertEqual(names(plan(files, RenameTemplate(pattern: "{folder} {kind} {time}"))),
                       ["d Image 12.00.HEIC", "d PDF 12.00.pdf"])
        XCTAssertEqual(names(plan([files[0]], RenameTemplate(pattern: "{unknown} x"))), ["{unknown} x.HEIC"],
                       "braces that aren't a token are kept")
    }

    func testFindReplaceAndCase() {
        let files = [item("/d/IMG_2041.jpg"), item("/d/img_2042.jpg")]
        XCTAssertEqual(names(plan(files, RenameTemplate(find: "img_", replace: "Goa "))), ["Goa 2041.jpg", "Goa 2042.jpg"])
        XCTAssertEqual(names(plan(files, RenameTemplate(caseStyle: .lower))), ["img_2041.jpg", "img_2042.jpg"])
        XCTAssertEqual(names(plan([item("/d/my holiday photo.png")], RenameTemplate(caseStyle: .title))), ["My Holiday Photo.png"])
    }

    func testNamesStayUniqueAndNeverTakeAnExistingFile() {
        let files = [item("/d/a.jpg"), item("/d/b.jpg"), item("/d/c.jpg")]
        let changes = plan(files, RenameTemplate(pattern: "Beach"), existing: ["/d": ["a.jpg", "b.jpg", "c.jpg", "Beach 2.jpg"]])
        XCTAssertEqual(names(changes), ["Beach.jpg", "Beach 3.jpg", "Beach 4.jpg"])
        XCTAssertEqual(changes.map(\.adjusted), [false, true, true])

        // A file already called "Beach.JPG" that isn't being renamed keeps its name (names ignore case).
        let more = plan([item("/d/x.jpg")], RenameTemplate(pattern: "Beach"), existing: ["/d": ["x.jpg", "beach.jpg"]])
        XCTAssertEqual(names(more), ["Beach 2.jpg"])
    }

    func testAFileThatKeepsItsNameIsNeverRenumbered() {
        // "b" asks for the name "a" already has, and "a" keeps it: "b" gets the number.
        let files = [item("/d/b.txt"), item("/d/a.txt")]
        let changes = plan(files, RenameTemplate(pattern: "a"), existing: ["/d": ["a.txt", "b.txt"]])
        XCTAssertEqual(names(changes), ["a 2.txt", "a.txt"])
        XCTAssertFalse(changes[1].isChange)
    }

    func testSwappingNamesNeedsTwoSteps() {
        let files = [item("/d/one.txt"), item("/d/two.txt")]
        let changes = plan(files, RenameTemplate(find: "one", replace: "x"), existing: ["/d": ["one.txt", "two.txt"]])
        XCTAssertFalse(RenamePlanner.needsTwoSteps(changes))
        let swap = [RenameChange(item: files[0], newName: "two.txt", adjusted: false),
                    RenameChange(item: files[1], newName: "one.txt", adjusted: false)]
        XCTAssertTrue(RenamePlanner.needsTwoSteps(swap))
        let caseOnly = [RenameChange(item: files[0], newName: "One.txt", adjusted: false)]
        XCTAssertTrue(RenamePlanner.needsTwoSteps(caseOnly), "changing only the case goes through a temporary name")
    }

    func testUnsafeCharactersAndLength() {
        let f = [item("/d/a.txt")]
        XCTAssertEqual(names(plan(f, RenameTemplate(pattern: "Q3/Q4: plan"))), ["Q3-Q4- plan.txt"])
        XCTAssertEqual(names(plan(f, RenameTemplate(pattern: "...hidden"))), ["hidden.txt"], "no leading dots")
        XCTAssertEqual(names(plan(f, RenameTemplate(pattern: "report.TXT"))), ["report.txt"], "typing the extension doesn't double it")
        XCTAssertEqual(names(plan(f, RenameTemplate(pattern: "   "))), ["a.txt"], "an empty result keeps the old name")
        let long = names(plan(f, RenameTemplate(pattern: String(repeating: "é", count: 300))))[0]
        XCTAssertLessThanOrEqual(long.utf8.count, 255)
        XCTAssertTrue(long.hasSuffix(".txt"))
    }

    func testFoldersKeepDotsInTheirNames() {
        let folder = item("/d/v1.2 release", kind: .folder)
        XCTAssertEqual(names(plan([folder], RenameTemplate(pattern: "{name} final"))), ["v1.2 release final"])
    }

    func testTitlesComeFromTheText() {
        let shot = item("/d/Screenshot 2025-10-12 at 09.41.22.png")
        let changes = plan([shot], .smart, text: [shot.path: "INVOICE #4821\nTotal due: 12,400\nPay by 30 Oct"])
        XCTAssertEqual(names(changes), ["2025-10-12 Invoice #4821.png"])
        // No text: the title is the current name.
        let plain = item("/d/notes.png")
        XCTAssertEqual(names(plan([plain], .smart)), ["2025-10-12 notes.png"])
    }

    func testSmartTitleSkipsNoise() {
        XCTAssertEqual(SmartTitle.title(from: "https://example.com/x\n12/10/2025\nBoarding Pass\nGate 42"), "Boarding Pass")
        XCTAssertEqual(SmartTitle.title(from: "Page 1 of 3\nQuarterly Report: Q3 revenue up 18% and more words here"),
                       "Quarterly Report Q3 revenue up 18%")
        XCTAssertNil(SmartTitle.title(from: "1234 5678\n--\n"))
        XCTAssertEqual(SmartTitle.title(from: "Wi-Fi password: HavenGuest2026"), "Wi-Fi password HavenGuest2026")
    }

    func testTakenDateFallsBackToCreated() {
        let photo = item("/d/p.jpg")
        let taken = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let ctx = RenameContext(takenDate: { _ in taken }, timeZone: utc)
        let t = RenameTemplate(pattern: "{date}", dateField: .taken)
        XCTAssertEqual(RenamePlanner.plan([photo], template: t, context: ctx) { _ in [] }.map(\.newName), ["2023-11-14.jpg"])
        XCTAssertEqual(names(plan([photo], t)), ["2025-10-12.jpg"])
    }

    func testPlanningThousandsIsQuick() {
        let files = (0..<20_000).map { item("/d/IMG_\($0).jpg") }
        let start = Date()
        let changes = plan(files, RenameTemplate(pattern: "Trip {n:5}"), existing: ["/d": files.map(\.name)])
        XCTAssertEqual(changes.count, 20_000)
        XCTAssertEqual(Set(changes.map(\.newName)).count, 20_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
