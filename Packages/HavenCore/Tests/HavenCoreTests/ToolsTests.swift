import XCTest
@testable import HavenCore

final class ToolsTests: XCTestCase {
    let d = Date(timeIntervalSince1970: 1_790_000_000)

    func item(_ path: String, folder: Bool = false) -> FileItem {
        FileItem(path: path, size: 1_000, created: d, modified: d, isDirectory: folder)
    }

    func testToolsFitTheFilesYouPick() {
        let jpg = item("/p/beach.jpg"), heic = item("/p/IMG_1.HEIC"), pdf = item("/p/a.pdf"), pdf2 = item("/p/b.pdf")
        let mov = item("/p/clip.mov"), mkv = item("/p/film.mkv"), m4a = item("/p/memo.m4a"), txt = item("/p/notes.txt")
        let srt = item("/p/talk.srt"), doc = item("/p/plan.docx"), folder = item("/p/Trip", folder: true)

        XCTAssertTrue(ToolID.convertImage.applies(to: [jpg, heic]))
        XCTAssertFalse(ToolID.convertImage.applies(to: [jpg, pdf]), "every file must fit")
        XCTAssertTrue(ToolID.removeBackground.applies(to: [heic]))
        XCTAssertTrue(ToolID.imagesToPDF.applies(to: [jpg, heic]))
        XCTAssertFalse(ToolID.mergePDFs.applies(to: [pdf]), "merging needs two")
        XCTAssertTrue(ToolID.mergePDFs.applies(to: [pdf, pdf2]))
        XCTAssertTrue(ToolID.splitPDF.applies(to: [pdf, pdf2]))
        XCTAssertFalse(ToolID.signPDF.applies(to: [pdf, pdf2]), "one at a time")
        XCTAssertTrue(ToolID.compressVideo.applies(to: [mov]))
        XCTAssertFalse(ToolID.compressVideo.applies(to: [mkv]), "macOS can't open MKV without other software")
        XCTAssertTrue(ToolID.transcribe.applies(to: [mov, m4a]))
        XCTAssertTrue(ToolID.convertAudio.applies(to: [m4a]))
        XCTAssertFalse(ToolID.convertAudio.applies(to: [mov]))
        XCTAssertTrue(ToolID.translate.applies(to: [srt]))
        XCTAssertTrue(ToolID.summarize.applies(to: [doc]))
        XCTAssertTrue(ToolID.summarize.applies(to: [txt]))
        XCTAssertFalse(ToolID.summarize.applies(to: [txt, doc]))
        XCTAssertTrue(ToolID.available(for: [folder]).isEmpty)
        XCTAssertEqual(ToolID.available(for: [pdf]), [.splitPDF, .organizePDF, .extractPDFPages, .pdfToImages, .lockPDF, .unlockPDF, .signPDF, .translate, .summarize])
        XCTAssertEqual(ToolID.mergePDFs.choosePrompt, "Choose two or more PDFs")
        XCTAssertEqual(ToolID.trimVideo.choosePrompt, "Choose a video")
        XCTAssertEqual(ToolID.transcribe.choosePrompt, "Choose one or more videos or audio files")
        // Every tool belongs to exactly one group, and each group lists its own.
        XCTAssertEqual(ToolGroup.allCases.flatMap(\.tools).count, ToolID.allCases.count)
        XCTAssertEqual(Set(ToolID.allCases.map(\.title)).count, ToolID.allCases.count, "titles are unique")
    }

    func testOutputNames() {
        let heic = item("/p/IMG_2041.HEIC"), png = item("/p/logo.png"), pdf = item("/p/Report.v2.pdf")
        XCTAssertEqual(ToolNaming.converted(heic, ext: "jpg"), "IMG_2041.jpg")
        XCTAssertEqual(ToolNaming.converted(png, ext: "png"), "logo (converted).png")
        XCTAssertEqual(ToolNaming.converted(item("/p/a.jpeg"), ext: "jpg"), "a (converted).jpg")
        XCTAssertEqual(ToolNaming.tagged(heic, "rotated"), "IMG_2041 (rotated).HEIC")
        XCTAssertEqual(ToolNaming.tagged(png, "cut out", ext: "png"), "logo (cut out).png")
        XCTAssertEqual(ToolNaming.merged([pdf, png], ext: "pdf"), "Report.v2 (merged).pdf")
        XCTAssertEqual(ToolNaming.folder(pdf, "pages"), "Report.v2 (pages)")
        XCTAssertEqual(ToolNaming.page("Report", 2, of: 12, ext: "pdf"), "Report - page 03.pdf")
        XCTAssertEqual(ToolNaming.page("Book", 4, of: 250, ext: "png"), "Book - page 005.png")
        XCTAssertEqual(ToolNaming.pdfFromImages([png]), "logo.pdf")
        XCTAssertEqual(ToolNaming.pdfFromImages([png, heic, heic]), "logo (3 pages).pdf")
        XCTAssertEqual(ToolNaming.tagged(item("/p/clip.mov"), PlaybackSpeed.double.tag), "clip (2×).mov")
    }

    func testOptions() {
        XCTAssertTrue(ResizeOption.percent(50).size(width: 4032, height: 3024) == (2016, 1512))
        XCTAssertTrue(ResizeOption.longestSide(2048).size(width: 3024, height: 4032) == (1536, 2048))
        XCTAssertTrue(ResizeOption.longestSide(2048).size(width: 800, height: 600) == (800, 600), "never enlarged")
        XCTAssertEqual(ResizeOption.longestSide(1600).tag, "1600px")
        XCTAssertTrue(VideoQuality.medium.size(width: 3840, height: 2160) == (1280, 720))
        XCTAssertTrue(VideoQuality.small.size(width: 1080, height: 1920) == (540, 960))
        XCTAssertTrue(VideoQuality.high.size(width: 641, height: 359) == (642, 360), "even sizes, never enlarged")
        XCTAssertEqual(ImageFormat.targets(for: [item("/p/a.png"), item("/p/b.png")]), [.jpeg, .heic, .tiff, .webp])
        XCTAssertEqual(ImageFormat.targets(for: [item("/p/a.png"), item("/p/b.jpg")]).count, 5, "mixed formats: every format")
        XCTAssertEqual(AudioFormat.targets(for: [item("/p/a.aif")]), [.m4a, .wav, .flac])
        XCTAssertEqual(PlaybackSpeed.half.tag, "0.5×")
        XCTAssertEqual(PlaybackSpeed.double.newDuration(10), 5)
        XCTAssertTrue(Rotation.left.swapsSides)
        XCTAssertFalse(Rotation.upsideDown.swapsSides)
    }

    func testPageRanges() {
        XCTAssertEqual(PageRange.parse("1-3, 5", pageCount: 10), [0, 1, 2, 4])
        XCTAssertEqual(PageRange.parse("8-", pageCount: 10), [7, 8, 9])
        XCTAssertEqual(PageRange.parse("-2", pageCount: 10), [0, 1])
        XCTAssertEqual(PageRange.parse("3–1", pageCount: 10), [2, 1, 0], "backwards ranges keep their order")
        XCTAssertEqual(PageRange.parse("2, 2, 1-2", pageCount: 10), [1, 0], "no repeats")
        XCTAssertNil(PageRange.parse("11", pageCount: 10))
        XCTAssertNil(PageRange.parse("a-b", pageCount: 10))
        XCTAssertNil(PageRange.parse("", pageCount: 10))
        XCTAssertEqual(PageRange.describe([0, 1, 2, 4, 6, 7]), "1–3, 5, 7–8")
        XCTAssertEqual(PageRange.tag([2]), "page 3")
        XCTAssertEqual(PageRange.tag([0, 1, 2]), "pages 1-3")
    }

    func testSubtitlesRoundTrip() {
        let cues = [Cue(start: 0, end: 2.5, text: "Hello there."), Cue(start: 2.5, end: 3725.5, text: " Second line\n\nwith a gap "),
                    Cue(start: 3726, end: 3727, text: "   ")]
        let srt = Subtitles.srt(cues)
        XCTAssertEqual(srt, "1\n00:00:00,000 --> 00:00:02,500\nHello there.\n\n2\n00:00:02,500 --> 01:02:05,500\nSecond line\nwith a gap\n")
        let back = Subtitles.parse(srt)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[1].end, 3725.5, accuracy: 0.0001)
        XCTAssertEqual(back[1].text, "Second line\nwith a gap")
        let vtt = "WEBVTT\n\n00:01.000 --> 00:04.250 align:start\nFrom a web video\n"
        XCTAssertEqual(Subtitles.parse(vtt), [Cue(start: 1, end: 4.25, text: "From a web video")])
        XCTAssertEqual(Subtitles.parse("1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows line ends\r\n").first?.text, "Windows line ends")
        XCTAssertEqual(Subtitles.timestamp(59.9996), "00:01:00,000")
    }

    func testTranscriptReadsInParagraphs() {
        let cues = [Cue(start: 0, end: 2, text: "Welcome everyone."), Cue(start: 2.2, end: 4, text: "Let's begin."),
                    Cue(start: 9, end: 11, text: "Next topic: the budget.")]
        XCTAssertEqual(Subtitles.plainText(cues), "Welcome everyone. Let's begin.\n\nNext topic: the budget.")
    }

    func testTextChunksStayUnderTheLimit() {
        let para = (1...40).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let text = ["Short intro.", para, "A closing paragraph."].joined(separator: "\n\n")
        let chunks = TextChunks.split(text, maxCharacters: 300)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 300 }, chunks.map(\.count).description)
        XCTAssertEqual(chunks.first, "Short intro.")
        XCTAssertTrue(chunks.last?.hasSuffix("A closing paragraph.") == true)
        let rejoined = chunks.joined(separator: " ").replacingOccurrences(of: "\n\n", with: " ")
        for n in [1, 17, 40] { XCTAssertTrue(rejoined.contains("Sentence number \(n) is here."), "nothing lost") }
        let wall = String(repeating: "x", count: 1_050)
        XCTAssertEqual(TextChunks.split(wall, maxCharacters: 500).map(\.count), [500, 500, 50], "text with no breaks is cut")
        XCTAssertEqual(TextChunks.split("   ", maxCharacters: 100), [])
    }

    func testGIFFrames() {
        let short = GIFPlan.frameTimes(duration: 2, fps: 10)
        XCTAssertEqual(short.count, 20)
        XCTAssertEqual(short[1], 0.1, accuracy: 0.0001)
        let long = GIFPlan.frameTimes(duration: 60, fps: 12, maxFrames: 240)
        XCTAssertEqual(long.count, 240, "long clips get fewer frames per second")
        XCTAssertLessThan(long.last!, 60)
        XCTAssertEqual(GIFPlan.delay(duration: 2, frames: 20), 0.1, accuracy: 0.0001)
        XCTAssertEqual(GIFPlan.frameTimes(duration: 0, fps: 10), [])
    }
    func testSpokenWordsFindVideosOnceTranscribed() {
        let video = item("/U/Movies/Standup.mov"), memo = item("/U/Music/Memo.m4a"), song = item("/U/Music/Song.mp3")
        let transcripts = [video.path: FileItem.fold("Today we review the quarterly budget"), memo.path: FileItem.fold("Remember to call the dentist")]
        let query = QueryParser.parse("budget").query
        let hits = SearchEngine.search(query, in: [video, memo, song], text: { transcripts[$0] })
        XCTAssertEqual(hits.map(\.name), ["Standup.mov"])
        XCTAssertEqual(SearchEngine.search(QueryParser.parse("dentist").query, in: [video, memo, song], text: { transcripts[$0] }).map(\.name), ["Memo.m4a"])
        XCTAssertTrue(FileKind.video.hasSearchableText)
        XCTAssertFalse(FileKind.archive.hasSearchableText)
    }
}
