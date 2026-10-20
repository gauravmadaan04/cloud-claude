import Foundation
@testable import HavenCore
import XCTest

/// Real ZIP files (made with Python's zipfile, DEFLATE-compressed) for the document readers.
enum ZipFixtures {
    static let docx = "UEsDBBQAAAAIAAAAIQDuR1hmHwAAAB0AAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLOxr8jNUShLLSrOzM+zVTLUM1Cyt7MJqSxILda3AwBQSwMEFAAAAAgAAAAhAEtw8i4oAQAACBAAABEAAAB3b3JkL2RvY3VtZW50LnhtbO3XzWrDMAwA4PueQriQ09Zky6ElaVLKys5j7R7AjdUk4MjGdvrz9rPX/bBR6Av4IoOtT5KPWixPg4QDGtsrqtjjNGOA1CjRU1ux9+3Lw5yBdZwEl4qwYme0bFnfLY6FUM04IDnwFcgWx4qdWO3vd0qcw6lDMCG4+s3ncQmr1iAGs0jDbYjmM+p/INQsrOaN76gNWjQHZPUWiZMr4NX0Zw5/avx02nTcDPzqG9+ll5w1amV7BwkfdAkm/CGZzPPZrMyz+yzLbk1XP/N9MnnK8xIUgesQWqNGErCXShlIpCtJOeipkaNAkbSuvDbQznzNs+lbQuHzYY2y62+3l3y06AfXyJ2He99UIrWum0LEEUccccQRRxxxxBFHHHHEEV9w+r2ip787fP0BUEsBAhQDFAAAAAgAAAAhAO5HWGYfAAAAHQAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAAACEAS3DyLigBAAAIEAAAEQAAAAAAAAAAAAAAgAFQAAAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAIAAgCAAAAApwEAAAAA"
    static let xlsx = "UEsDBBQAAAAIAAAAIQCGRLmnTwAAAHsAAAAPAAAAeGwvd29ya2Jvb2sueG1ssynPL8pOys/PtrMpzkhNLSmG0gp5ibmptkpOpSnpQI6RgZGZkgJYwjPFVslQSR9VWUhRZkGxglpiboG1QkhRYllqDpJqI5BqfZjp+nALAVBLAwQUAAAACAAAACEAT7yXYk0AAAB0AAAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1ssykuLlFIzi/NK7FVMlaysynOtLMpsXMvyk9OLcpMLbbRL7Gz0QcJgnARSC4oNa9EASJeBBVySc3JyIQLwZWX2Pkm5qXnI5uiD7TODgBQSwMEFAAAAAgAAAAhAEWSPaAxAAAASAAAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWyzKc8vyi7OSE0tsbMBUy6JJYl2NkX55XY2yXY2ZXaGNvpldjb6QLY+WFAfSZU+QjMAUEsBAhQDFAAAAAgAAAAhAIZEuadPAAAAewAAAA8AAAAAAAAAAAAAAIABAAAAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAIAAAAIQBPvJdiTQAAAHQAAAAUAAAAAAAAAAAAAACAAXwAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbFBLAQIUAxQAAAAIAAAAIQBFkj2gMQAAAEgAAAAYAAAAAAAAAAAAAACAAfsAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAMAAwDFAAAAYgEAAAAA"
    static let pptx = "UEsDBBQAAAAIAAAAIQDVpHPOKwAAADsAAAAVAAAAcHB0L3NsaWRlcy9zbGlkZTEueG1ssymwKs5JsbNJtCoAEUUgosTOJ7E0LzlDISAnMc9GHyQAIovAJFCZPkQPAFBLAwQUAAAACAAAACEAveYG+jQAAABEAAAAFgAAAHBwdC9zbGlkZXMvc2xpZGUxMC54bWyzKbAqzkmxs0m0KgARRSCixC44JzMlVaEkNc9KoSQjMS9boTK/1EYfJAMii8AkUL0+RDMAUEsDBBQAAAAAAAAAIQAaBsjKOQAAADkAAAAVAAAAcHB0L3NsaWRlcy9zbGlkZTIueG1sPHA6c2xkPjxhOnA+PGE6cj48YTp0PlBoYXNlIHR3bzwvYTp0PjwvYTpyPjwvYTpwPjwvcDpzbGQ+UEsDBBQAAAAIAAAAIQCC2RzVEgAAABAAAAAgAAAAcHB0L3NsaWRlcy9fcmVscy9zbGlkZTEueG1sLnJlbHOzCUrNSSzJzM8rzsgsKNa3AwBQSwECFAMUAAAACAAAACEA1aRzzisAAAA7AAAAFQAAAAAAAAAAAAAAgAEAAAAAcHB0L3NsaWRlcy9zbGlkZTEueG1sUEsBAhQDFAAAAAgAAAAhAL3mBvo0AAAARAAAABYAAAAAAAAAAAAAAIABXgAAAHBwdC9zbGlkZXMvc2xpZGUxMC54bWxQSwECFAMUAAAAAAAAACEAGgbIyjkAAAA5AAAAFQAAAAAAAAAAAAAAgAHGAAAAcHB0L3NsaWRlcy9zbGlkZTIueG1sUEsBAhQDFAAAAAgAAAAhAILZHNUSAAAAEAAAACAAAAAAAAAAAAAAAIABMgEAAHBwdC9zbGlkZXMvX3JlbHMvc2xpZGUxLnhtbC5yZWxzUEsFBgAAAAAEAAQAGAEAAIIBAAAAAA=="
    static let odt = "UEsDBBQAAAAAAAAAIQBexjIMJwAAACcAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi92bmQub2FzaXMub3BlbmRvY3VtZW50LnRleHRQSwMEFAAAAAgAAAAhAJDYrlNlAAAAuQAAAAsAAABjb250ZW50LnhtbHWOsQqAMAxEv0iyS8ng7kfUJlUHm6Kp2L9XaRE6uCS8Oy4XI96vjnsSlzYO2jkJ+mw01ZiE8gfK1+O8s19wXENSPgxULnrEIdHMWugAtDHucjIVQe0EqEI211xEA811aIrh778bUEsBAhQDFAAAAAAAAAAhAF7GMgwnAAAAJwAAAAgAAAAAAAAAAAAAAIABAAAAAG1pbWV0eXBlUEsBAhQDFAAAAAgAAAAhAJDYrlNlAAAAuQAAAAsAAAAAAAAAAAAAAIABTQAAAGNvbnRlbnQueG1sUEsFBgAAAAACAAIAbwAAANsAAAAAAA=="
    static let epub = "UEsDBBQAAAAAAAAAIQBvYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAACAAAACEAESgAbXwAAACmAAAADwAAAE9FQlBTL2NoMi54aHRtbCWOwQnDMAxFVwkZoKLXVtWlK2QBOxLY4MZGEWlD6e4V9knSR+/xMdmrECYJTGjZitDyrghjxd1OH+271lL1psI/hJEhDCZWPp2/0jOFZqJTx/3GRkuSSfPhIUaKsvGOEOmC0Ny8am5GR9Dp85hTZpZtvrt95P7YxdD7/QFQSwMEFAAAAAgAAAAhAIRSn6xQAAAAVwAAAA8AAABPRUJQUy9jaDEueGh0bWwlzDEKgDAMAMCvxAfE4B6yOIiTb0g1WMGmRbL4e0XHW45zlFM41e0WzoOMWVvYBYsb02tuMgck29XhcJiq9kxNuEMEhbWWYh6AKEz/QV/4AFBLAwQUAAAACAAAACEAyXVNNyoAAAAyAAAADwAAAE9FQlBTL25hdi54aHRtbLPJKMnNsbNJyk+ptLPJSyyzc87PK0nNKylWyMksLrHRBwnZ6EOk9cFqAVBLAQIUAxQAAAAAAAAAIQBvYassFAAAABQAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAAAAIQARKABtfAAAAKYAAAAPAAAAAAAAAAAAAACAAToAAABPRUJQUy9jaDIueGh0bWxQSwECFAMUAAAACAAAACEAhFKfrFAAAABXAAAADwAAAAAAAAAAAAAAgAHjAAAAT0VCUFMvY2gxLnhodG1sUEsBAhQDFAAAAAgAAAAhAMl1TTcqAAAAMgAAAA8AAAAAAAAAAAAAAIABYAEAAE9FQlBTL25hdi54aHRtbFBLBQYAAAAABAAEAO0AAAC3AQAAAAA="
    static let pages = "UEsDBBQAAAAIAAAAIQB7nHe0CgAAAAgAAAASAAAASW5kZXgvRG9jdW1lbnQuaXdhY2BMysxLLKoEAFBLAwQUAAAAAAAAACEAMH8NMGwBAABsAQAACwAAAHByZXZpZXcuanBn/9j/4GZha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc2Zha2UtcHJldmlldy1ieXRlc1BLAQIUAxQAAAAIAAAAIQB7nHe0CgAAAAgAAAASAAAAAAAAAAAAAACAAQAAAABJbmRleC9Eb2N1bWVudC5pd2FQSwECFAMUAAAAAAAAACEAMH8NMGwBAABsAQAACwAAAAAAAAAAAAAAgAE6AAAAcHJldmlldy5qcGdQSwUGAAAAAAIAAgB5AAAAzwEAAAAA"
    static let bomb = "UEsDBBQAAAAIAAAAIQBJLXdt4QMAAEdCDwAHAAAAYmlnLnhtbO3BAREAAAQEsEgKOF2+hfiC2NaZBQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3urKHFBLAQIUAxQAAAAIAAAAIQBJLXdt4QMAAEdCDwAHAAAAAAAAAAAAAACAAQAAAABiaWcueG1sUEsFBgAAAAABAAEANQAAAAYEAAAAAA=="

    static func data(_ b64: String) -> Data { Data(base64Encoded: b64)! }
}

final class DocumentTextTests: XCTestCase {
    override func tearDown() {
        Inflate.portableOnly = false
    }

    func text(_ b64: String, _ ext: String) throws -> String {
        let zip = try ZipArchive(data: ZipFixtures.data(b64))
        return try XCTUnwrap(DocumentText.extract(zip: zip, ext: ext))
    }

    func checkAllFormats() throws {
        let docx = try text(ZipFixtures.docx, "docx")
        XCTAssertTrue(docx.hasPrefix("Rental Agreement\nTenant: Priya Sharma Deposit & rent ₹30,000\nCafé on the ground floor <not included>\nSigned in Delhi"), docx)
        XCTAssertEqual(docx.components(separatedBy: "Clause repeated").count - 1, 60, "every repeated paragraph is decoded")

        XCTAssertEqual(try text(ZipFixtures.xlsx, "xlsx"), "Budget 2026\nTrips & Travel\nGroceries\nRent Delhi\nMangoes")
        XCTAssertEqual(try text(ZipFixtures.pptx, "pptx"), "Launch Plan\nPhase two\nSlide ten: thank you", "slides in their real order")
        XCTAssertEqual(try text(ZipFixtures.odt, "odt"), "Minutes\nBudget approved today")
        XCTAssertEqual(try text(ZipFixtures.epub, "epub"), "Chapter One\nIt began in Goa.\nTwo\nChapter Two\nThe river bends.",
                       "chapters in order, without scripts, styles, comments or the table of contents")
    }

    func testOfficeAndEbookTextWithTheSystemDecoder() throws {
        try checkAllFormats()
    }

    func testOfficeAndEbookTextWithThePortableDecoder() throws {
        Inflate.portableOnly = true
        try checkAllFormats()
    }

    func testIWorkPreviewIsFound() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-iwork-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Plan.pages")
        try ZipFixtures.data(ZipFixtures.pages).write(to: file)
        let preview = try XCTUnwrap(DocumentText.iWorkPreview(url: file))
        XCTAssertEqual(Array(preview.prefix(3)), [0xFF, 0xD8, 0xFF])
        // A package (folder) version of the same thing.
        let package = dir.appendingPathComponent("Old.key")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("QuickLook"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: package.appendingPathComponent("QuickLook/Thumbnail.jpg"))
        XCTAssertEqual(DocumentText.iWorkPreview(url: package), Data([1, 2, 3]))
    }

    func testHugeEntriesAreCapped() throws {
        let zip = try ZipArchive(data: ZipFixtures.data(ZipFixtures.bomb))
        let entry = try XCTUnwrap(zip.entry(named: "big.xml"))
        XCTAssertEqual(entry.uncompressedSize, 1_000_007)
        XCTAssertLessThanOrEqual(try zip.read(entry, limit: 4096).count, 4096)
        Inflate.portableOnly = true
        XCTAssertLessThanOrEqual(try zip.read(entry, limit: 4096).count, 4096)
        XCTAssertEqual(try zip.read(entry).count, 1_000_007)
    }

    func testDamagedFilesFailQuietly() {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip at all, just some text".utf8)))
        let good = ZipFixtures.data(ZipFixtures.docx)
        XCTAssertThrowsError(try ZipArchive(data: good.prefix(good.count - 30)), "cut short")
        // Flip bytes inside the compressed document: reading fails or returns junk, but never crashes.
        var bad = good
        for i in 120..<200 where i < bad.count { bad[i] ^= 0x5A }
        if let zip = try? ZipArchive(data: bad) {
            for portable in [false, true] {
                Inflate.portableOnly = portable
                _ = DocumentText.extract(zip: zip, ext: "docx")
            }
        }
        XCTAssertNil(DocumentText.extract(url: URL(fileURLWithPath: "/nonexistent/file.docx")))
    }

    func testXMLTextDetails() {
        XCTAssertEqual(DocumentText.xmlText(Array("<p>a&#x41;&#66;&nbsp;c &unknown; d</p>".utf8)), "aAB c &unknown; d")
        XCTAssertEqual(DocumentText.xmlText(Array("<a title=\"x>y\">kept</a><![CDATA[raw <b>]]>".utf8)), "keptraw <b>")
        XCTAssertEqual(DocumentText.xmlText(Array("<html><SCRIPT>hide()</SCRIPT><p>show</p></html>".utf8), html: true), "show")
        XCTAssertEqual(DocumentText.xmlText(Array(String(repeating: "<p>word</p>", count: 1000).utf8), limit: 50).count, 50)
    }
}
