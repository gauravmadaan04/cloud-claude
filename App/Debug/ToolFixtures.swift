#if DEBUG
import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sample files for the tools: a photo that says where it was taken, a picture with a clear subject,
/// multi-page PDFs, short videos with sound, and a spoken voice memo (debug builds only).
extension FixtureFactory {
    static let spokenMemo = "Welcome to the planning meeting. Today we review the quarterly budget and the launch date."

    static func makeTools(at root: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        func dir(_ rel: String) -> String {
            let p = (root as NSString).appendingPathComponent(rel)
            try? fm.createDirectory(atPath: p, withIntermediateDirectories: true)
            return p
        }
        for d in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Applications"] { _ = dir(d) }
        let pictures = dir("Pictures"), documents = dir("Documents"), movies = dir("Movies"), music = dir("Music")
        let now = Date()
        func at(_ folder: String, _ name: String) -> String { (folder as NSString).appendingPathComponent(name) }

        photoWithDetails(to: at(pictures, "Goa Trip.jpg"))
        subject(to: at(pictures, "Red Apple.png"))
        scene(seed: 3, size: CGSize(width: 1600, height: 1200), to: at(pictures, "Hills.heic"), type: .heic)
        pdf(pages: [["Contract", "Page one: alpha terms"], ["Contract", "Page two: bravo terms"], ["Contract", "Page three: charlie terms"]],
            to: at(documents, "Contract.pdf"))
        pdf(pages: [["Appendix", "Page one: delta"], ["Appendix", "Page two: echo"]], to: at(documents, "Appendix.pdf"))
        try? """
        Team update

        The new office opens in March. Everyone gets a desk by the window and a locker.

        The launch moves to Friday because the printer needs two more days. Please send your slides by Thursday.
        """.write(toFile: at(documents, "Meeting Notes.txt"), atomically: true, encoding: .utf8)
        video(seconds: 3, size: CGSize(width: 1280, height: 720), detailed: true, to: at(movies, "Beach Clip.mov"))
        video(seconds: 2, size: CGSize(width: 1280, height: 720), hue: 0.6, to: at(movies, "Sunset Clip.mov"))
        speech(spokenMemo, to: at(music, "Voice Memo.m4a"))
        wav(seconds: 3, frequency: 523, to: at(music, "Chime.wav"))

        for (i, path) in [at(pictures, "Goa Trip.jpg"), at(pictures, "Red Apple.png"), at(pictures, "Hills.heic"), at(documents, "Contract.pdf"),
                          at(documents, "Appendix.pdf"), at(documents, "Meeting Notes.txt"), at(movies, "Beach Clip.mov"),
                          at(movies, "Sunset Clip.mov"), at(music, "Voice Memo.m4a"), at(music, "Chime.wav")].enumerated() {
            mark(path, date: now.addingTimeInterval(-Double(i + 1) * 3600))
        }
    }

    /// A JPEG that says where (Goa), with what (an iPhone) and when it was taken.
    static func photoWithDetails(to path: String, size: CGSize = CGSize(width: 1600, height: 1200)) {
        guard let ctx = context(size) else { return }
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(0x2B78E4), cg(0xA7D3FF)] as CFArray, locations: nil) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        ctx.setFillColor(cg(0xF4D58D))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.3))
        ctx.setFillColor(cg(0xFFF4B0))
        ctx.fillEllipse(in: CGRect(x: size.width * 0.7, y: size.height * 0.62, width: 160, height: 160))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 15.4909, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 73.8278, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:12 09:41:22",
                                             kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera"],
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// A shiny red apple with a leaf, alone on a light table: an obvious subject to cut out.
    static func subject(to path: String, size: CGSize = CGSize(width: 1200, height: 900)) {
        guard let ctx = context(size) else { return }
        ctx.setFillColor(cg(0xEDEAE4))
        ctx.fill(CGRect(origin: .zero, size: size))
        let c = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        let r: CGFloat = 230
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.18))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r - 40, width: r * 1.8, height: 70))
        ctx.saveGState()
        let body = CGMutablePath()
        body.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 1.05, height: r * 1.95))
        body.addEllipse(in: CGRect(x: c.x - r * 0.05, y: c.y - r, width: r * 1.05, height: r * 1.95))
        ctx.addPath(body)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(0xFF5A4E), cg(0xB3121A), cg(0x6E0A10)] as CFArray,
                              locations: [0, 0.6, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - 70, y: c.y + 90), startRadius: 10, endCenter: c, endRadius: r * 1.2, options: [])
        }
        ctx.restoreGState()
        ctx.setFillColor(cg(0x5B3A1E))
        ctx.fill(CGRect(x: c.x - 8, y: c.y + r * 0.85, width: 16, height: 80))
        ctx.setFillColor(cg(0x3FA34D))
        ctx.fillEllipse(in: CGRect(x: c.x + 10, y: c.y + r * 0.95, width: 110, height: 50))
        if let img = ctx.makeImage() { save(img, to: path, type: .png) }
    }

    /// A PDF with a page per entry (title, then lines).
    static func pdf(pages: [[String]], to path: String) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil) else { return }
        for lines in pages {
            ctx.beginPDFPage(nil)
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            var y: CGFloat = 700
            for (i, line) in lines.enumerated() {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: i == 0 ? 30 : 18, weight: i == 0 ? .bold : .regular),
                                                            .foregroundColor: NSColor.black]
                (line as NSString).draw(at: NSPoint(x: 64, y: y), withAttributes: attrs)
                y -= i == 0 ? 54 : 30
            }
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Something said out loud, recorded with macOS's own voice.
    static func speech(_ text: String, to path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-o", path, "--file-format=m4af", "--data-format=aac", text]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    /// An H.264 video with a moving square over a colour wash, and (optionally) a tone as its soundtrack.
    /// `detailed` adds fine, changing texture (like real footage), so the video isn't trivially small.
    static func video(seconds: Double, size: CGSize = CGSize(width: 640, height: 360), fps: Int32 = 30, hue: CGFloat = 0.08,
                      audio: Bool = true, detailed: Bool = false, to path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: path.lowercased().hasSuffix(".mp4") ? .mp4 : .mov) else { return }
        let w = Int(size.width), h = Int(size.height)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        videoIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(videoIn)
        var audioIn: AVAssetWriterInput?
        if audio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                                                         AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            a.expectsMediaDataInRealTime = false
            writer.add(a)
            audioIn = a
        }
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        let frames = Int(seconds * Double(fps))
        var frame = 0
        group.enter()
        videoIn.requestMediaDataWhenReady(on: DispatchQueue(label: "fixture.video")) {
            while videoIn.isReadyForMoreMediaData {
                if frame >= frames {
                    videoIn.markAsFinished()
                    group.leave()
                    return
                }
                if let pool = adaptor.pixelBufferPool, let pb = drawFrame(frame, of: frames, pool: pool, hue: hue, detailed: detailed) {
                    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
                }
                frame += 1
            }
        }
        if let audioIn {
            let rate = 44_100
            let total = Int(seconds * Double(rate))
            var sample = 0
            group.enter()
            audioIn.requestMediaDataWhenReady(on: DispatchQueue(label: "fixture.audio")) {
                while audioIn.isReadyForMoreMediaData {
                    if sample >= total {
                        audioIn.markAsFinished()
                        group.leave()
                        return
                    }
                    let n = min(4_096, total - sample)
                    if let buffer = toneBuffer(start: sample, count: n, rate: rate) { audioIn.append(buffer) }
                    sample += n
                }
            }
        }
        group.wait()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }

    private static func drawFrame(_ i: Int, of count: Int, pool: CVPixelBufferPool, hue: CGFloat, detailed: Bool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let t = CGFloat(i) / CGFloat(max(1, count))
        ctx.setFillColor(NSColor(hue: (hue + t * 0.2).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.9, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if detailed {
            // Grain that changes every frame, like footage from a camera.
            var seed = UInt64(i &+ 1) &* 0x9E37_79B9_7F4A_7C15
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 40) / CGFloat(1 << 24)
            }
            for _ in 0..<2_500 {
                ctx.setFillColor(CGColor(gray: next(), alpha: 0.6))
                ctx.fill(CGRect(x: next() * CGFloat(w), y: next() * CGFloat(h), width: 3 + next() * 9, height: 3 + next() * 9))
            }
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        let side = CGFloat(h) / 3
        ctx.fill(CGRect(x: (CGFloat(w) - side) * t, y: (CGFloat(h) - side) / 2, width: side, height: side))
        return pb
    }

    private static func toneBuffer(start: Int, count: Int, rate: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr, let format else { return nil }
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(start + i) / Double(rate)
            samples[i] = Int16(sin(2 * .pi * 440 * t) * 9_000)
        }
        let length = count * 2
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return nil }
        var out: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                                                             presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
                                                             packetDescriptions: nil, sampleBufferOut: &out)
        return out
    }
}
#endif
