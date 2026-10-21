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
        XCTAssertTrue(ImageTools.privateDetails(URL(fileURLWithPath: photo)).location, "the original keeps everything")

        // A GIF can't be copied as is: it becomes a clean PNG.
        let gif = path("Wave.gif")
        FixtureFactory.scene(seed: 1, size: CGSize(width: 300, height: 200), to: gif, type: .gif)
        do { let value = try await run(.removeImageDetails, [gif]); XCTAssertEqual(value, ["Wave (clean).png"]) }
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

    func testSigning() async throws {
        let p = path("Lease.pdf")
        FixtureFactory.pdf(pages: [["Lease", "page one"], ["Lease", "sign here"]], to: p)
        let ink = FixtureFactory.context(CGSize(width: 300, height: 100))!
        ink.setStrokeColor(CGColor(red: 0, green: 0, blue: 0.6, alpha: 1))
        ink.setLineWidth(8)
        ink.move(to: CGPoint(x: 10, y: 50))
        ink.addCurve(to: CGPoint(x: 290, y: 50), control1: CGPoint(x: 100, y: 120), control2: CGPoint(x: 200, y: -20))
        ink.strokePath()
        var extras = ToolExtras()
        let rect = CGRect(x: 300, y: 100, width: 240, height: 80)
        extras.signature = SignaturePlacement(page: 1, rect: rect, image: ink.makeImage()!)
        do { let value = try await run(.signPDF, [p], .none, extras); XCTAssertEqual(value, ["Lease (signed).pdf"]) }
        let signed = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path("Lease (signed).pdf"))))
        XCTAssertEqual(signed.pageCount, 2)
        XCTAssertTrue(signed.page(at: 1)!.string?.contains("sign here") == true, "the page's text is still text")
        // The signature shows where it was placed.
        let picture = try XCTUnwrap(PDFTools.render(signed.page(at: 1)!, dpi: 72))
        let rep = NSBitmapImageRep(cgImage: picture)
        var inked = 0
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 4) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
                // Bitmap rows run top to bottom; PDF points bottom to top.
                if let c = rep.colorAt(x: x, y: picture.height - y), c.blueComponent > c.redComponent + 0.2 { inked += 1 }
            }
        }
        XCTAssertGreaterThan(inked, 10, "blue ink inside the placed rectangle")
        XCTAssertEqual(PDFDocument(url: URL(fileURLWithPath: p))?.page(at: 1)?.string?.contains("sign here"), true)
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
