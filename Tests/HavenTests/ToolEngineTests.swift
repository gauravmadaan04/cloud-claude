// Uses the sample-file generator, which only exists in debug builds.
#if DEBUG
import AppKit
import AVFoundation
import HavenCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Haven

/// Every tool on real files in a temporary folder: images, PDFs, video, audio and Whisper transcription.
final class ToolEngineTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haven-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
    func item(_ p: String) -> FileItem { FileScanner.item(at: URL(fileURLWithPath: p), rootID: "t")! }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: path(name)) }
    func names() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []) }

    func props(_ p: String) -> [CFString: Any] {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [:] }
        return props
    }

    func size(_ p: String) -> (Int, Int) {
        let pr = props(p)
        return (pr[kCGImagePropertyPixelWidth] as? Int ?? 0, pr[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    func type(_ p: String) -> String? {
        CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    func duration(_ p: String) async -> Double { await MediaTools.duration(URL(fileURLWithPath: p)) }

    func tracks(_ p: String, _ type: AVMediaType) async -> Int {
        (try? await AVURLAsset(url: URL(fileURLWithPath: p)).loadTracks(withMediaType: type).count) ?? 0
    }

    func run(_ tool: ToolID, _ paths: [String], _ choice: ToolChoice = .none, _ extras: ToolExtras = ToolExtras()) async throws -> [String] {
        let outcome = try await ToolWork.run(tool, paths.map(item), choice: choice, extras: extras)
        return outcome.made.map { ($0.to as NSString).lastPathComponent }
    }

    // MARK: Images

    func testConvertResizeAndRotateImages() async throws {
        let photo = path("Hills.jpg")
        FixtureFactory.scene(seed: 2, size: CGSize(width: 1400, height: 1000), to: photo, type: .jpeg)
        do { let value = try await run(.convertImage, [photo], .imageFormat(.png)); XCTAssertEqual(value, ["Hills.png"]) }
        XCTAssertEqual(type(path("Hills.png")), UTType.png.identifier)
        XCTAssertTrue(size(path("Hills.png")) == (1400, 1000))
        for format in ImageTools.writableFormats where format != .jpeg && format != .png {
            let made = try await run(.convertImage, [photo], .imageFormat(format))
            XCTAssertEqual(type(path(made[0])), format.typeIdentifier, "\(format) is written as \(format)")
        }
        XCTAssertTrue(ImageTools.writableFormats.contains(.heic), "HEIC is written on every supported Mac")

        do { let value = try await run(.resizeImage, [photo], .resize(.percent(50))); XCTAssertEqual(value, ["Hills (50%).jpg"]) }
        XCTAssertTrue(size(path("Hills (50%).jpg")) == (700, 500))
        do { let value = try await run(.resizeImage, [photo], .resize(.longestSide(800))); XCTAssertEqual(value, ["Hills (800px).jpg"]) }
        XCTAssertTrue(size(path("Hills (800px).jpg")) == (800, 571))

        do { let value = try await run(.rotateImage, [photo], .rotation(.right)); XCTAssertEqual(value, ["Hills (rotated).jpg"]) }
        XCTAssertTrue(size(path("Hills (rotated).jpg")) == (1000, 1400), "a quarter turn swaps the sides")
        do { let value = try await run(.rotateImage, [photo], .rotation(.upsideDown)); XCTAssertEqual(value, ["Hills (rotated) 2.jpg"], "names never clash") }
        XCTAssertTrue(size(path("Hills (rotated) 2.jpg")) == (1400, 1000))

        // A batch: every file gets its own copy.
        let other = path("Lake.png")
        FixtureFactory.scene(seed: 5, size: CGSize(width: 600, height: 400), to: other, type: .png)
        let made = try await run(.convertImage, [photo, other], .imageFormat(.tiff))
        XCTAssertEqual(Set(made), ["Hills 2.tiff", "Lake.tiff"], "Hills.tiff exists already, so the new one is numbered")
        XCTAssertTrue(exists("Hills.jpg") && exists("Lake.png"), "originals stay")
    }

    func testRotationTurnsThePictureTheRightWay() async throws {
        // Left half red, right half blue: after a right turn, red is on top.
        let p = path("Halves.png")
        let ctx = FixtureFactory.context(CGSize(width: 400, height: 200))!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        FixtureFactory.save(ctx.makeImage()!, to: p, type: .png)
        _ = try await run(.rotateImage, [p], .rotation(.right))
        let rotated = try XCTUnwrap(NSImage(contentsOfFile: path("Halves (rotated).png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: rotated)
        let top = try XCTUnwrap(rep.colorAt(x: 100, y: 50)), bottom = try XCTUnwrap(rep.colorAt(x: 100, y: 350))
        XCTAssertGreaterThan(top.redComponent, 0.8, "red ends up on top")
        XCTAssertGreaterThan(bottom.blueComponent, 0.8)
    }

    func testRemovingPrivateDetails() async throws {
        let photo = path("Goa Trip.jpg")
        FixtureFactory.photoWithDetails(to: photo)
        let before = ImageTools.privateDetails(URL(fileURLWithPath: photo))
        XCTAssertTrue(before.location && before.camera && before.date, "the sample photo says where, how and when")
        do { let value = try await run(.removeImageDetails, [photo]); XCTAssertEqual(value, ["Goa Trip (clean).jpg"]) }
        let after = ImageTools.privateDetails(URL(fileURLWithPath: path("Goa Trip (clean).jpg")))
        XCTAssertFalse(after.any, "\(after)")
        XCTAssertTrue(size(path("Goa Trip (clean).jpg")) == size(photo))
        let bytes = { (p: String) in MediaTools.size(URL(fileURLWithPath: p)) }
        XCTAssertLessThanOrEqual(bytes(path("Goa Trip (clean).jpg")), bytes(photo) + 2_000, "the picture is copied, not re-compressed")
        XCTAssertTrue(ImageTools.privateDetails(URL(fileURLWithPath: photo)).location, "the original keeps everything")

        // A GIF can't be copied as is: it becomes a clean PNG.
        let gif = path("Wave.gif")
        FixtureFactory.scene(seed: 1, size: CGSize(width: 300, height: 200), to: gif, type: .gif)
        do { let value = try await run(.removeImageDetails, [gif]); XCTAssertEqual(value, ["Wave (clean).png"]) }
    }

    func testCleanJPEGKeepsItsTurnAndItsPicture() throws {
        // A photo stored sideways (as phones do) that says where it was taken.
        let p = path("Sideways.jpg")
        let ctx = FixtureFactory.context(CGSize(width: 300, height: 200))!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyOrientation: 6,
                                                            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.97, kCGImagePropertyGPSLatitudeRef: "N"],
                                                            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Pixel 9"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let original = [UInt8](try Data(contentsOf: URL(fileURLWithPath: p)))
        let clean = try XCTUnwrap(JPEGDetails.strip(original, orientation: 6))
        try Data(clean).write(to: URL(fileURLWithPath: path("clean.jpg")))
        let cleanProps = props(path("clean.jpg"))
        XCTAssertEqual(cleanProps[kCGImagePropertyOrientation] as? Int, 6, "still shown the right way up")
        XCTAssertNil(cleanProps[kCGImagePropertyGPSDictionary])
        XCTAssertFalse(ImageTools.privateDetails(URL(fileURLWithPath: path("clean.jpg"))).any)
        func picture(_ b: [UInt8]) -> ArraySlice<UInt8> {
            var i = 2
            while i + 4 < b.count, b[i] == 0xFF, b[i + 1] != 0xDA { i += 2 + (Int(b[i + 2]) << 8 | Int(b[i + 3])) }
            return b[i...]
        }
        XCTAssertEqual(picture(original), picture(clean), "the compressed picture is the very same bytes")
        XCTAssertNil(JPEGDetails.strip([0x89, 0x50, 0x4E, 0x47], orientation: 1), "not a JPEG")
    }

    func testRemovingTheBackground() async throws {
        let p = path("Red Apple.png")
        FixtureFactory.subject(to: p)
        do { let value = try await run(.removeBackground, [p]); XCTAssertEqual(value, ["Red Apple (cut out).png"]) }
        let out = try XCTUnwrap(NSImage(contentsOfFile: path("Red Apple (cut out).png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertTrue(ImageTools.hasAlpha(out))
        let rep = NSBitmapImageRep(cgImage: out)
        XCTAssertLessThan(rep.colorAt(x: 10, y: 10)?.alphaComponent ?? 1, 0.05, "the table is gone")
        XCTAssertGreaterThan(rep.colorAt(x: out.width / 2, y: out.height / 2 + 20)?.alphaComponent ?? 0, 0.9, "the apple stays")
    }

    // MARK: PDF

    func pdfText(_ p: String, page: Int) -> String { PDFDocument(url: URL(fileURLWithPath: p))?.page(at: page)?.string ?? "" }
    func pages(_ p: String) -> Int { PDFDocument(url: URL(fileURLWithPath: p))?.pageCount ?? 0 }

    func testPDFMergeSplitAndPages() async throws {
        let contract = path("Contract.pdf"), appendix = path("Appendix.pdf")
        FixtureFactory.pdf(pages: [["Contract", "alpha"], ["Contract", "bravo"], ["Contract", "charlie"]], to: contract)
        FixtureFactory.pdf(pages: [["Appendix", "delta"], ["Appendix", "echo"]], to: appendix)

        do { let value = try await run(.mergePDFs, [appendix, contract]); XCTAssertEqual(value, ["Appendix (merged).pdf"]) }
        let merged = path("Appendix (merged).pdf")
        XCTAssertEqual(pages(merged), 5)
        XCTAssertTrue(pdfText(merged, page: 0).contains("delta") && pdfText(merged, page: 4).contains("charlie"), "in the order picked")

        do { let value = try await run(.splitPDF, [contract]); XCTAssertEqual(value, ["Contract (pages)"]) }
        let parts = try FileManager.default.contentsOfDirectory(atPath: path("Contract (pages)")).sorted()
        XCTAssertEqual(parts, ["Contract - page 01.pdf", "Contract - page 02.pdf", "Contract - page 03.pdf"])
        XCTAssertTrue(pdfText(path("Contract (pages)/Contract - page 02.pdf"), page: 0).contains("bravo"))

        var extras = ToolExtras()
        extras.pages = [PageEdit(source: 2, rotation: 90), PageEdit(source: 0)]
        do { let value = try await run(.organizePDF, [contract], .none, extras); XCTAssertEqual(value, ["Contract (edited).pdf"]) }
        let edited = PDFDocument(url: URL(fileURLWithPath: path("Contract (edited).pdf")))!
        XCTAssertEqual(edited.pageCount, 2, "the page left out is gone")
        XCTAssertTrue(edited.page(at: 0)!.string!.contains("charlie"))
        XCTAssertEqual(edited.page(at: 0)!.rotation, 90)

        extras.pages = [PageEdit(source: 1), PageEdit(source: 2)]
        do { let value = try await run(.extractPDFPages, [contract], .none, extras); XCTAssertEqual(value, ["Contract (pages 2-3).pdf"]) }
        XCTAssertEqual(pages(path("Contract (pages 2-3).pdf")), 2)

        do { let value = try await run(.pdfToImages, [appendix]); XCTAssertEqual(value, ["Appendix (images)"]) }
        let images = try FileManager.default.contentsOfDirectory(atPath: path("Appendix (images)")).sorted()
        XCTAssertEqual(images, ["Appendix - page 01.png", "Appendix - page 02.png"])
        XCTAssertTrue(size(path("Appendix (images)/Appendix - page 01.png")) == (1275, 1650), "150 dpi letter pages")
        XCTAssertEqual(pages(contract), 3, "the original is untouched")
    }

    func testImagesBecomeAPDF() async throws {
        let a = path("Scan 1.jpg"), b = path("Scan 2.png")
        FixtureFactory.scene(seed: 4, size: CGSize(width: 1200, height: 1600), to: a, type: .jpeg)
        FixtureFactory.scene(seed: 6, size: CGSize(width: 1600, height: 1200), to: b, type: .png)
        do { let value = try await run(.imagesToPDF, [a, b]); XCTAssertEqual(value, ["Scan 1 (2 pages).pdf"]) }
        let doc = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Scan 1 (2 pages).pdf"))))
        XCTAssertEqual(doc.pageCount, 2)
        let first = doc.page(at: 0)!.bounds(for: .mediaBox), second = doc.page(at: 1)!.bounds(for: .mediaBox)
        XCTAssertEqual(first.height, 842, accuracy: 1)
        XCTAssertEqual(first.width / first.height, 0.75, accuracy: 0.01, "pages are shaped like the pictures")
        XCTAssertGreaterThan(second.width, second.height)
    }

    func testPasswords() async throws {
        let p = path("Private.pdf")
        FixtureFactory.pdf(pages: [["Private", "secret plans"]], to: p)
        var extras = ToolExtras()
        extras.password = "mango42"
        do { let value = try await run(.lockPDF, [p], .none, extras); XCTAssertEqual(value, ["Private (locked).pdf"]) }
        let locked = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Private (locked).pdf"))))
        XCTAssertTrue(locked.isEncrypted && locked.isLocked)
        XCTAssertTrue(locked.unlock(withPassword: "mango42"))

        extras.password = "wrong"
        do {
            _ = try await run(.unlockPDF, [path("Private (locked).pdf")], .none, extras)
            XCTFail("a wrong password must not unlock")
        } catch ToolError.wrongPassword {}
        extras.password = "mango42"
        do { let value = try await run(.unlockPDF, [path("Private (locked).pdf")], .none, extras); XCTAssertEqual(value, ["Private (locked) (unlocked).pdf"]) }
        let open = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Private (locked) (unlocked).pdf"))))
        XCTAssertFalse(open.isEncrypted)
        XCTAssertTrue(open.page(at: 0)!.string!.contains("secret plans"))
    }

    // MARK: Fill & Sign

    /// A two-page application: page one has two form fields, page two is where you sign.
    func makeForm(_ name: String) throws -> String {
        let p = path(name)
        FixtureFactory.pdf(pages: [["Application", "Full name", "Email"], ["Application", "sign here"]], to: p)
        let doc = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: p)))
        let page = try XCTUnwrap(doc.page(at: 0))
        for (i, field) in ["Full Name", "Email"].enumerated() {
            let w = PDFAnnotation(bounds: CGRect(x: 240, y: 640 - CGFloat(i) * 40, width: 260, height: 22), forType: .widget, withProperties: nil)
            w.widgetFieldType = .text
            w.fieldName = field
            page.addAnnotation(w)
        }
        XCTAssertTrue(doc.write(to: URL(fileURLWithPath: p)))
        return p
    }

    /// What the Fill & Sign window hands over: the document (with any form answers) and the items to draw.
    func fillExtras(_ p: String, _ items: [FillItem], lockForm: Bool = true, prepare: (PDFDocument) -> Void = { _ in }) throws -> ToolExtras {
        let doc = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: p)))
        prepare(doc)
        var extras = ToolExtras()
        extras.fill = FillPlan(base: try XCTUnwrap(doc.dataRepresentation()), items: items, lockForm: lockForm)
        return extras
    }

    func inkImage() -> CGImage {
        let ink = FixtureFactory.context(CGSize(width: 300, height: 100))!
        ink.setStrokeColor(CGColor(red: 0, green: 0, blue: 0.6, alpha: 1))
        ink.setLineWidth(8)
        ink.move(to: CGPoint(x: 10, y: 50))
        ink.addCurve(to: CGPoint(x: 290, y: 50), control1: CGPoint(x: 100, y: 120), control2: CGPoint(x: 200, y: -20))
        ink.strokePath()
        return ink.makeImage()!
    }

    func textItem(_ text: String, page: Int, at point: CGPoint) -> FillItem {
        let size = FillDrawing.textSize(text, fontSize: 13)
        return FillItem(page: page, center: CGPoint(x: point.x + size.width / 2, y: point.y), size: size, content: .text(text))
    }

    /// How many sampled points in a region (page points) of a rendered page pass the test.
    func pixels(_ page: PDFPage, in rect: CGRect, _ test: (NSColor) -> Bool) throws -> Int {
        let picture = try XCTUnwrap(PDFTools.render(page, dpi: 72))
        let rep = NSBitmapImageRep(cgImage: picture)
        var n = 0
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2) {
                // Bitmap rows run top to bottom; PDF points bottom to top.
                if let c = rep.colorAt(x: x, y: picture.height - y)?.usingColorSpace(.sRGB), test(c) { n += 1 }
            }
        }
        return n
    }

    func testFillAndSign() async throws {
        let p = try makeForm("Application.pdf")
        let sig = CGRect(x: 300, y: 100, width: 240, height: 80)
        let items = [
            textItem("Flat 4B, Linden Court", page: 1, at: CGPoint(x: 72, y: 300)),
            textItem("13 November 2026", page: 1, at: CGPoint(x: 72, y: 270)),
            FillItem(page: 1, center: CGPoint(x: sig.midX, y: sig.midY), size: sig.size, content: .image(inkImage(), initials: false)),
            FillItem(page: 1, center: CGPoint(x: 80, y: 200), size: CGSize(width: 16, height: 16), content: .mark(.check)),
        ]
        let extras = try fillExtras(p, items) { doc in
            for a in doc.page(at: 0)!.annotations where a.type == "Widget" {
                a.widgetStringValue = a.fieldName == "Full Name" ? "Asha Rao" : "asha@example.com"
            }
        }
        do { let value = try await run(.signPDF, [p], .none, extras); XCTAssertEqual(value, ["Application (signed).pdf"]) }
        let done = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Application (signed).pdf"))))
        XCTAssertEqual(done.pageCount, 2)
        let signPage = try XCTUnwrap(done.page(at: 1))
        let text = signPage.string ?? ""
        XCTAssertTrue(text.contains("sign here"), "the page's own text is still text")
        XCTAssertTrue(text.contains("Flat 4B, Linden Court"), "typed text is real text: \(text)")
        XCTAssertTrue(text.contains("13 November 2026"))
        XCTAssertGreaterThan(try pixels(signPage, in: sig) { $0.blueComponent > $0.redComponent + 0.2 }, 10, "the signature is where it was put")
        XCTAssertGreaterThan(try pixels(signPage, in: CGRect(x: 70, y: 190, width: 20, height: 20)) { $0.brightnessComponent < 0.5 }, 3, "the tick")

        // The form is locked: its answers are now plain content.
        let formPage = try XCTUnwrap(done.page(at: 0))
        XCTAssertFalse(formPage.annotations.contains { $0.type == "Widget" }, "no fields left to change")
        XCTAssertGreaterThan(try pixels(formPage, in: CGRect(x: 240, y: 640, width: 200, height: 22)) { $0.brightnessComponent < 0.5 }, 3,
                             "the answer shows where the field was")
        XCTAssertTrue((formPage.string ?? "").contains("Asha Rao"), "answers stay searchable: \(formPage.string ?? "")")

        // The original is untouched.
        let original = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: p)))
        XCTAssertEqual(original.page(at: 0)?.annotations.filter { $0.type == "Widget" }.count, 2)
        XCTAssertFalse(original.page(at: 1)?.string?.contains("Flat 4B") ?? true)
    }

    func testFilledFormStaysFillable() async throws {
        let p = try makeForm("Membership.pdf")
        let extras = try fillExtras(p, [], lockForm: false) { doc in
            doc.page(at: 0)!.annotations.first { $0.fieldName == "Full Name" }?.widgetStringValue = "Asha Rao"
        }
        do { let value = try await run(.signPDF, [p], .none, extras); XCTAssertEqual(value, ["Membership (filled).pdf"]) }
        let done = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Membership (filled).pdf"))))
        let fields = done.page(at: 0)?.annotations.filter { $0.type == "Widget" } ?? []
        XCTAssertEqual(fields.count, 2, "fields are still fields")
        XCTAssertEqual(fields.first { $0.fieldName == "Full Name" }?.widgetStringValue, "Asha Rao")
    }

    func testRedactionRemovesTheText() async throws {
        let p = path("Statement.pdf")
        FixtureFactory.pdf(pages: [["Statement", "Account 12345678 belongs to Asha", "Balance 2,10,500"]], to: p)
        XCTAssertTrue(PDFDocument(url: URL(fileURLWithPath: p))!.page(at: 0)!.string!.contains("12345678"))
        // The second line sits on a baseline at y 646 (18 pt): cover it.
        let box = FillItem(page: 0, center: CGPoint(x: 320, y: 652), size: CGSize(width: 520, height: 30), content: .redaction)
        do { let value = try await run(.signPDF, [p], .none, try fillExtras(p, [box])); XCTAssertEqual(value, ["Statement (filled).pdf"]) }
        let page = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Statement (filled).pdf")))?.page(at: 0))
        XCTAssertFalse((page.string ?? "").contains("12345678"), "nothing under a redaction survives")
        XCTAssertGreaterThan(try pixels(page, in: CGRect(x: 100, y: 642, width: 300, height: 18)) { $0.brightnessComponent < 0.15 }, 50, "a black box")
        XCTAssertGreaterThan(try pixels(page, in: CGRect(x: 64, y: 616, width: 200, height: 14)) { $0.brightnessComponent < 0.5 }, 3,
                             "the rest of the page still shows")
    }

    func testFillingATurnedPage() async throws {
        let p = path("Turned.pdf")
        FixtureFactory.pdf(pages: [["Landscape form", "Sign below"]], to: p)
        let doc = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: p)))
        doc.page(at: 0)!.rotation = 90
        XCTAssertTrue(doc.write(to: URL(fileURLWithPath: p)))
        let item = textItem("Asha Rao", page: 0, at: CGPoint(x: 300, y: 300))
        do { let value = try await run(.signPDF, [p], .none, try fillExtras(p, [item])); XCTAssertEqual(value, ["Turned (filled).pdf"]) }
        let page = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Turned (filled).pdf")))?.page(at: 0))
        XCTAssertEqual(page.rotation, 90, "the page keeps its turn")
        XCTAssertTrue((page.string ?? "").contains("Asha Rao"))
        XCTAssertTrue((page.string ?? "").contains("Sign below"))
    }

    func testHighlightsAreKept() async throws {
        let p = path("Notes.pdf")
        FixtureFactory.pdf(pages: [["Notes", "Read this part"], ["Notes", "And this"]], to: p)
        let band = CGRect(x: 64, y: 644, width: 160, height: 20)
        let extras = try fillExtras(p, [textItem("Seen", page: 1, at: CGPoint(x: 72, y: 500))], lockForm: false) { doc in
            for i in 0..<2 {
                let h = PDFAnnotation(bounds: band, forType: .highlight, withProperties: nil)
                h.color = NSColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 0.45)
                h.quadrilateralPoints = [NSValue(point: NSPoint(x: 0, y: band.height)), NSValue(point: NSPoint(x: band.width, y: band.height)),
                                         NSValue(point: .zero), NSValue(point: NSPoint(x: band.width, y: 0))]
                doc.page(at: i)!.addAnnotation(h)
            }
        }
        _ = try await run(.signPDF, [p], .none, extras)
        let done = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Notes (filled).pdf"))))
        XCTAssertTrue(done.page(at: 0)!.annotations.contains { $0.type == "Highlight" }, "a page with nothing added keeps its highlight as a highlight")
        let flat = try XCTUnwrap(done.page(at: 1))
        XCTAssertFalse(flat.annotations.contains { $0.type == "Highlight" })
        XCTAssertGreaterThan(try pixels(flat, in: band) { $0.blueComponent < $0.redComponent - 0.25 }, 10, "and on a page with something added, it's drawn in")
    }

    func testSignatureMaker() throws {
        if let hand = SignatureMaker.hands.first {
            let typed = try XCTUnwrap(SignatureMaker.typed("Asha Rao", hand: hand))
            XCTAssertGreaterThan(typed.width, typed.height, "a name is wider than it is tall")
        }
        XCTAssertNil(SignatureMaker.typed("   ", hand: SignatureMaker.Hand(name: "Snell Roundhand", postScript: "SnellRoundhand")))

        // A photo of a signature on slightly grey paper: the paper goes, the ink stays.
        let photo = path("signature photo.jpg")
        let ctx = FixtureFactory.context(CGSize(width: 800, height: 400))!
        ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.2, alpha: 1))
        ctx.setLineWidth(10)
        ctx.move(to: CGPoint(x: 200, y: 200))
        ctx.addCurve(to: CGPoint(x: 600, y: 200), control1: CGPoint(x: 300, y: 320), control2: CGPoint(x: 500, y: 80))
        ctx.strokePath()
        FixtureFactory.save(ctx.makeImage()!, to: photo, type: .jpeg)
        let cut = try XCTUnwrap(SignatureMaker.fromPhoto(URL(fileURLWithPath: photo)))
        XCTAssertLessThan(cut.width, 500, "cropped to the ink")
        let rep = NSBitmapImageRep(cgImage: cut)
        XCTAssertLessThan(rep.colorAt(x: 1, y: 1)?.alphaComponent ?? 1, 0.1, "the paper is see-through")
        var solid = 0
        for x in stride(from: 0, to: cut.width, by: 3) {
            for y in stride(from: 0, to: cut.height, by: 3) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.8 { solid += 1 }
        }
        XCTAssertGreaterThan(solid, 20, "the ink is kept")
    }

    // MARK: Video

    func testVideoTools() async throws {
        let clip = path("Beach.mov"), second = path("Sunset.mov")
        FixtureFactory.video(seconds: 3, size: CGSize(width: 1280, height: 720), detailed: true, to: clip)
        FixtureFactory.video(seconds: 2, size: CGSize(width: 1280, height: 720), hue: 0.6, to: second)
        let original = await duration(clip)
        XCTAssertEqual(original, 3, accuracy: 0.1)

        do { let value = try await run(.compressVideo, [clip], .videoQuality(.small)); XCTAssertEqual(value, ["Beach (540p).mp4"]) }
        XCTAssertLessThan(MediaTools.size(URL(fileURLWithPath: path("Beach (540p).mp4"))), MediaTools.size(URL(fileURLWithPath: clip)))
        let track = try await AVURLAsset(url: URL(fileURLWithPath: path("Beach (540p).mp4"))).loadTracks(withMediaType: .video).first!
        let natural = try await track.load(.naturalSize)
        XCTAssertEqual(max(natural.width, natural.height), 960, accuracy: 2)

        do { let value = try await run(.convertVideo, [clip], .container(.mp4)); XCTAssertEqual(value, ["Beach.mp4"]) }
        do { let value = await duration(path("Beach.mp4")); XCTAssertEqual(value, original, accuracy: 0.1) }

        var extras = ToolExtras()
        extras.timeRange = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        do { let value = try await run(.trimVideo, [clip], .none, extras); XCTAssertEqual(value, ["Beach (trimmed).mov"]) }
        do { let value = await duration(path("Beach (trimmed).mov")); XCTAssertEqual(value, 1, accuracy: 0.2) }

        do { let value = try await run(.videoToGIF, [clip], .gif(.small)); XCTAssertEqual(value, ["Beach.gif"]) }
        let gif = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path("Beach.gif")) as CFURL, nil))
        XCTAssertGreaterThanOrEqual(CGImageSourceGetCount(gif), 30, "12 frames a second")
        let gifSize = size(path("Beach.gif"))
        XCTAssertEqual(gifSize.0, 320)

        do { let value = try await run(.extractAudio, [clip]); XCTAssertEqual(value, ["Beach.m4a"]) }
        let soundOnly = await tracks(path("Beach.m4a"), .video), sound = await tracks(path("Beach.m4a"), .audio)
        XCTAssertEqual(soundOnly, 0)
        XCTAssertEqual(sound, 1)

        do { let value = try await run(.muteVideo, [clip]); XCTAssertEqual(value, ["Beach (muted).mov"]) }
        let mutedAudio = await tracks(path("Beach (muted).mov"), .audio), mutedVideo = await tracks(path("Beach (muted).mov"), .video)
        XCTAssertEqual(mutedAudio, 0)
        XCTAssertEqual(mutedVideo, 1)

        do { let value = try await run(.mergeVideos, [clip, second]); XCTAssertEqual(value, ["Beach (merged).mov"]) }
        do { let value = await duration(path("Beach (merged).mov")); XCTAssertEqual(value, 5, accuracy: 0.2) }

        do { let value = try await run(.changeSpeed, [clip], .speed(.double)); XCTAssertEqual(value, ["Beach (2×).mov"]) }
        do { let value = await duration(path("Beach (2×).mov")); XCTAssertEqual(value, 1.5, accuracy: 0.15) }
        XCTAssertTrue(exists("Beach.mov"))
    }

    func testCancellingLeavesNothingBehind() async throws {
        let clip = path("Long.mov")
        FixtureFactory.video(seconds: 12, size: CGSize(width: 1920, height: 1080), audio: false, to: clip)
        let task = Task { try await ToolWork.run(.compressVideo, [item(clip)], choice: .videoQuality(.small)) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled job must not finish")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(names(), ["Long.mov"], "no half-made file")
    }

    // MARK: Audio

    func testAudioTools() async throws {
        let wav = path("Chime.wav")
        FixtureFactory.wav(seconds: 3, frequency: 523, to: wav)
        for format in [AudioFormat.m4a, .aiff, .flac] {
            let made = try await run(.convertAudio, [wav], .audioFormat(format))
            XCTAssertEqual(made, ["Chime.\(format.ext)"])
            do { let value = await duration(path(made[0])); XCTAssertEqual(value, 3, accuracy: 0.1, "\(format)") }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path(made[0])))
            XCTAssertGreaterThan(file.length, 100_000)
        }
        do { let value = try await run(.convertAudio, [path("Chime.m4a")], .audioFormat(.wav)); XCTAssertEqual(value, ["Chime 2.wav"], "the original WAV is never replaced") }

        var extras = ToolExtras()
        extras.timeRange = CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        do { let value = try await run(.trimAudio, [wav], .none, extras); XCTAssertEqual(value, ["Chime (trimmed).m4a"]) }
        do { let value = await duration(path("Chime (trimmed).m4a")); XCTAssertEqual(value, 1, accuracy: 0.1) }
    }

    // MARK: Whisper

    static let testModel = "/Users/Shared/haven-test-models/ggml-base.en-q5_1.bin"

    @MainActor
    func testTranscriptionWithWhisper() async throws {
        guard FileManager.default.fileExists(atPath: Self.testModel) else {
            XCTFail("Missing the test model: run scripts/fetch-test-model.sh")
            return
        }
        let memo = path("Voice Memo.m4a")
        FixtureFactory.speech(FixtureFactory.spokenMemo, to: memo)
        do { let value = await duration(memo); XCTAssertGreaterThan(value, 3) }
        var extras = ToolExtras()
        extras.model = Self.testModel
        extras.transcriptFormats = [.text, .subtitles]
        let made = try await run(.transcribe, [memo], .none, extras)
        XCTAssertEqual(made, ["Voice Memo.txt", "Voice Memo.srt"])
        let text = try String(contentsOfFile: path("Voice Memo.txt"), encoding: .utf8).lowercased()
        for word in ["planning", "meeting", "budget", "launch"] {
            XCTAssertTrue(text.contains(word), "heard “\(word)” in: \(text)")
        }
        let cues = Subtitles.parse(try String(contentsOfFile: path("Voice Memo.srt"), encoding: .utf8))
        XCTAssertFalse(cues.isEmpty)
        XCTAssertLessThan(cues.first!.start, 1.5)
        XCTAssertTrue(LibraryStore.shared.text.store.raw(for: item(memo).path)?.lowercased().contains("budget") == true,
                      "what was said is searchable")

        // Speech in a video's soundtrack works the same way.
        let silent = path("Talk.mov")
        FixtureFactory.video(seconds: 1, audio: false, to: silent)
        do {
            _ = try await run(.transcribe, [silent], .none, extras)
            XCTFail("a video without sound has nothing to transcribe")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no sound"), error.localizedDescription)
        }
    }

    func testModelDownloadsAreCheckedBeforeUse() async throws {
        let source = dir.appendingPathComponent("model.bin")
        try Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 9) }).write(to: source)
        let expected = try WhisperModels.sha256(of: source)
        XCTAssertEqual(expected.count, 64)
        let temp = try await ModelDownloader(progress: { _ in }).download(source)
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertEqual(try WhisperModels.sha256(of: temp), expected, "the download arrives intact")
        XCTAssertNotEqual(temp.path, source.path)
        // The published checksums are the real ones (64 hex characters each).
        for model in WhisperModel.allCases {
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertTrue(model.url.absoluteString.hasSuffix(model.fileName))
        }
    }

    func testToolMenusOfferOnlyWhatMakesSense() {
        let png = FileItem(path: "/p/a.png", size: 1, created: Date(), modified: Date())
        let titles = ToolID.convertImage.choices(for: [png]).map(\.title)
        XCTAssertFalse(titles.contains("PNG"), "not the format it already has")
        XCTAssertTrue(titles.contains("JPEG"))
        XCTAssertEqual(ToolID.compressVideo.choices(for: []).count, 3)
        XCTAssertTrue(ToolID.signPDF.opensSheet)
        XCTAssertFalse(ToolID.rotateImage.opensSheet)
    }
}
#endif
