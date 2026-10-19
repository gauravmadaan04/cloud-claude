#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import HavenCore
import ImageIO
import UniformTypeIdentifiers

/// Builds a realistic sample home folder for UI tests and demos (debug builds only).
/// Layout: <root>/Desktop, Documents, Downloads, Pictures, Movies, Music, Applications.
enum FixtureFactory {
    static let day: TimeInterval = 86_400

    /// A date inside last calendar week (Wednesday), so "last week" searches find it.
    static var lastWeekMidpoint: Date {
        let start = DateSpec.lastWeek.resolve(now: Date(), calendar: .current).start ?? Date().addingTimeInterval(-9 * day)
        return start.addingTimeInterval(2 * day + 11 * 3600)
    }

    static func make(at root: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        func dir(_ rel: String) -> String {
            let p = (root as NSString).appendingPathComponent(rel)
            try? fm.createDirectory(atPath: p, withIntermediateDirectories: true)
            return p
        }
        let desktop = dir("Desktop")
        let documents = dir("Documents")
        let taxes = dir("Documents/Taxes")
        let downloads = dir("Downloads")
        let trips = dir("Pictures/Trips")
        let pictures = dir("Pictures")
        let movies = dir("Movies")
        let music = dir("Music")
        let apps = dir("Applications")
        let now = Date()

        // Screenshots on the Desktop (text inside for OCR).
        let shot1 = (desktop as NSString).appendingPathComponent("Screenshot 2026-10-12 at 09.41.22.png")
        image(lines: ["Boarding Pass", "DEL → BOM  ·  Gate 42", "Seat 14A"], palette: [0x2B78E4, 0x64A6FF], size: CGSize(width: 1600, height: 1000), to: shot1)
        mark(shot1, date: lastWeekMidpoint, screenshot: true)

        let shot2 = (desktop as NSString).appendingPathComponent("Screenshot 2026-08-02 at 18.10.05.png")
        image(lines: ["Meeting notes", "Launch moves to Friday", "Budget approved"], palette: [0xFFF1C7, 0xFFC93D], dark: true, size: CGSize(width: 1400, height: 900), to: shot2)
        mark(shot2, date: now.addingTimeInterval(-75 * day), screenshot: true)

        let shot3 = (desktop as NSString).appendingPathComponent("Screenshot 2026-10-18 at 11.02.40.png")
        image(lines: ["Wi-Fi password", "HavenGuest2026"], palette: [0x7352F0, 0xA38BFF], size: CGSize(width: 1200, height: 800), to: shot3)
        mark(shot3, date: now.addingTimeInterval(-1 * day), screenshot: true)

        // Documents.
        pdf(lines: ["Income Tax Return", "Assessment Year 2025-26", "Total income: 14,20,000", "Refund due: 18,400"],
            to: (taxes as NSString).appendingPathComponent("Tax Return 2025.pdf"))
        mark((taxes as NSString).appendingPathComponent("Tax Return 2025.pdf"), date: now.addingTimeInterval(-40 * day))
        text("Month,Rent,Groceries,Travel\nJan,30000,12000,4000\nFeb,30000,11000,9000\n",
             to: (taxes as NSString).appendingPathComponent("Budget 2026.csv"), date: now.addingTimeInterval(-20 * day))
        pdf(lines: ["Project Plan", "Phase 1: research", "Phase 2: build", "Phase 3: launch"],
            to: (documents as NSString).appendingPathComponent("Project Plan.pdf"))
        mark((documents as NSString).appendingPathComponent("Project Plan.pdf"), date: now)
        text("# Reading list\n\n- The Overstory\n- Atomic Habits\n", to: (documents as NSString).appendingPathComponent("Reading List.md"),
             date: now.addingTimeInterval(-12 * day))
        richText("Gaurav's résumé\nProduct designer, Delhi\nExperience: 8 years",
                 to: (documents as NSString).appendingPathComponent("Resume.rtf"), date: now.addingTimeInterval(-90 * day))
        tag((documents as NSString).appendingPathComponent("Project Plan.pdf"), ["Work"])

        // Downloads from different places.
        let q3 = (downloads as NSString).appendingPathComponent("Q3-report.pdf")
        pdf(lines: ["Quarterly Report", "Q3 revenue up 18%", "Prepared for the board"], to: q3)
        XAttr.setWhereFroms(["https://mail-attachment.googleusercontent.com/attachment/u/0/?ui=2&ik=abc", "https://mail.google.com/"], path: q3)
        XAttr.setQuarantine(agent: "Google Chrome", path: q3)
        mark(q3, date: lastWeekMidpoint)

        let invoice = (downloads as NSString).appendingPathComponent("invoice-4821.png")
        image(lines: ["INVOICE #4821", "Total due: 12,400", "Pay by 30 Oct"], palette: [0xFFFFFF, 0xEDEDED], dark: true, size: CGSize(width: 1200, height: 1500), to: invoice)
        XAttr.setWhereFroms(["https://mail-attachment.googleusercontent.com/attachment/u/0/?ui=2&ik=def", "https://mail.google.com/"], path: invoice)
        mark(invoice, date: now.addingTimeInterval(-2 * day))

        let design = (downloads as NSString).appendingPathComponent("design-final.png")
        image(lines: ["Diwali Sale", "Up to 40% off"], palette: [0xE84A75, 0xFFB4C6], size: CGSize(width: 1080, height: 1080), to: design)
        XAttr.setWhereFroms(["https://export-download.canva.com/abc/design.png", "https://www.canva.com/design/xyz"], path: design)
        mark(design, date: now.addingTimeInterval(-4 * day))

        let diagram = (downloads as NSString).appendingPathComponent("chatgpt-diagram.png")
        image(lines: ["System diagram", "App → API → Database"], palette: [0x10A37F, 0x7CDDC0], size: CGSize(width: 1400, height: 900), to: diagram)
        XAttr.setWhereFroms(["https://files.oaiusercontent.com/file-123", "https://chatgpt.com/c/456"], path: diagram)
        mark(diagram, date: now.addingTimeInterval(-6 * day))

        let whatsapp = (downloads as NSString).appendingPathComponent("WhatsApp Image 2026-10-15.jpeg")
        scene(seed: 3, size: CGSize(width: 1200, height: 900), to: whatsapp, type: .jpeg)
        XAttr.setWhereFroms(["blob:https://web.whatsapp.com/5d3e-11"], path: whatsapp)
        mark(whatsapp, date: now.addingTimeInterval(-5 * day))

        let airdrop = (downloads as NSString).appendingPathComponent("IMG_7781.jpeg")
        scene(seed: 4, size: CGSize(width: 1200, height: 900), to: airdrop, type: .jpeg)
        XAttr.setQuarantine(agent: "sharingd", path: airdrop)
        mark(airdrop, date: now.addingTimeInterval(-8 * day))

        let repo = (downloads as NSString).appendingPathComponent("haven-main.zip")
        bytes(size: 2_400_000, seed: 9, to: repo)
        XAttr.setWhereFroms(["https://codeload.github.com/example/haven/zip/refs/heads/main", "https://github.com/example/haven"], path: repo)
        mark(repo, date: now.addingTimeInterval(-15 * day))

        let installer = (downloads as NSString).appendingPathComponent("Zoom-6.2.pkg")
        sparse(size: 52_000_000, to: installer)
        XAttr.setWhereFroms(["https://zoom.us/client/latest/Zoom.pkg", "https://zoom.us/download"], path: installer)
        mark(installer, date: now.addingTimeInterval(-60 * day))

        let dmg = (downloads as NSString).appendingPathComponent("Figma-124.dmg")
        sparse(size: 128_000_000, to: dmg)
        XAttr.setWhereFroms(["https://desktop.figma.com/mac/Figma.dmg", "https://www.figma.com/downloads/"], path: dmg)
        mark(dmg, date: now.addingTimeInterval(-95 * day))

        let statement = (downloads as NSString).appendingPathComponent("bank-statement-march.pdf")
        pdf(lines: ["Account statement", "March 2026", "Closing balance 2,10,500"], to: statement)
        XAttr.setWhereFroms(["https://netbanking.examplebank.co.in/statements/march.pdf", "https://netbanking.examplebank.co.in/"], path: statement)
        mark(statement, date: now.addingTimeInterval(-200 * day))

        let photosZip = (downloads as NSString).appendingPathComponent("holiday-photos.zip")
        bytes(size: 3_100_000, seed: 2, to: photosZip)
        mark(photosZip, date: now.addingTimeInterval(-30 * day))
        let unzipped = dir("Downloads/holiday-photos")
        scene(seed: 7, size: CGSize(width: 1000, height: 750), to: (unzipped as NSString).appendingPathComponent("beach-day.jpg"), type: .jpeg)

        // Photos: identical copies and look-alikes.
        let goa = (trips as NSString).appendingPathComponent("Goa Beach.jpg")
        scene(seed: 1, size: CGSize(width: 1600, height: 1200), to: goa, type: .jpeg)
        mark(goa, date: now.addingTimeInterval(-120 * day))
        let goaCopy = (downloads as NSString).appendingPathComponent("Goa Beach (1).jpg")
        try? fm.copyItem(atPath: goa, toPath: goaCopy)
        mark(goaCopy, date: now.addingTimeInterval(-10 * day))
        let goaCopy2 = (desktop as NSString).appendingPathComponent("Goa Beach copy.jpg")
        try? fm.copyItem(atPath: goa, toPath: goaCopy2)
        mark(goaCopy2, date: now.addingTimeInterval(-9 * day))

        let sunset = (trips as NSString).appendingPathComponent("IMG_2041.jpg")
        scene(seed: 5, size: CGSize(width: 1600, height: 1200), to: sunset, type: .jpeg)
        let sunsetHEIC = (trips as NSString).appendingPathComponent("IMG_2041.heic")
        scene(seed: 5, size: CGSize(width: 1600, height: 1200), to: sunsetHEIC, type: .heic, brightness: 0.04)
        mark(sunset, date: now.addingTimeInterval(-50 * day))
        mark(sunsetHEIC, date: now.addingTimeInterval(-50 * day))

        for (i, name) in ["Mountains.jpg", "City Lights.jpg", "Garden.jpg", "Lake.jpg"].enumerated() {
            let p = (pictures as NSString).appendingPathComponent(name)
            scene(seed: 11 + i, size: CGSize(width: 1400, height: 1000), to: p, type: .jpeg)
            mark(p, date: now.addingTimeInterval(-Double(20 + i * 17) * day))
        }

        // Video and music.
        let holiday = (movies as NSString).appendingPathComponent("Holiday 2023.mov")
        sparse(size: 900_000_000, to: holiday)
        mark(holiday, date: now.addingTimeInterval(-420 * day))
        let tune = (music as NSString).appendingPathComponent("Morning Tune.wav")
        wav(seconds: 4, frequency: 440, to: tune)
        mark(tune, date: now.addingTimeInterval(-7 * day))
        let tune2 = (music as NSString).appendingPathComponent("Evening Tune.wav")
        wav(seconds: 3, frequency: 330, to: tune2)
        mark(tune2, date: now.addingTimeInterval(-25 * day))

        // Apps: one unused for months, one used yesterday.
        app(named: "Old Editor", in: apps, lastUsed: now.addingTimeInterval(-200 * day), added: now.addingTimeInterval(-400 * day))
        app(named: "Daily Notes", in: apps, lastUsed: now.addingTimeInterval(-1 * day), added: now.addingTimeInterval(-300 * day))
    }

    // MARK: Writers

    static func mark(_ path: String, date: Date, screenshot: Bool = false) {
        try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: path)
        XAttr.setTestAddedDate(date, path: path)
        if screenshot { XAttr.setScreenCapture(path: path) }
    }

    static func tag(_ path: String, _ tags: [String]) {
        try? (URL(fileURLWithPath: path) as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    static func text(_ s: String, to path: String, date: Date) {
        try? s.write(toFile: path, atomically: true, encoding: .utf8)
        mark(path, date: date)
    }

    static func richText(_ s: String, to path: String, date: Date) {
        let attributed = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        if let data = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        mark(path, date: date)
    }

    static func bytes(size: Int, seed: UInt8, to path: String) {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { buf in
            guard let p = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var x = UInt32(seed) &* 2_654_435_761
            for i in 0..<size {
                x ^= x << 13; x ^= x >> 17; x ^= x << 5
                p[i] = UInt8(truncatingIfNeeded: x)
            }
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// A large file that takes no disk space.
    static func sparse(size: UInt64, to path: String) {
        FileManager.default.createFile(atPath: path, contents: Data("HAVEN".utf8))
        if let h = FileHandle(forWritingAtPath: path) {
            try? h.truncate(atOffset: size)
            try? h.close()
        }
    }

    static func app(named name: String, in dir: String, lastUsed: Date, added: Date) {
        let fm = FileManager.default
        let bundle = (dir as NSString).appendingPathComponent(name + ".app")
        let macos = (bundle as NSString).appendingPathComponent("Contents/MacOS")
        try? fm.createDirectory(atPath: macos, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleName": name, "CFBundleIdentifier": "app.haven.fixture.\(name.replacingOccurrences(of: " ", with: ""))",
            "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL", "CFBundleExecutable": name,
        ]
        (plist as NSDictionary).write(toFile: (bundle as NSString).appendingPathComponent("Contents/Info.plist"), atomically: true)
        bytes(size: 1_500_000, seed: UInt8(name.count), to: (macos as NSString).appendingPathComponent(name))
        try? fm.setAttributes([.creationDate: added, .modificationDate: added], ofItemAtPath: bundle)
        XAttr.setTestAddedDate(added, path: bundle)
        XAttr.setLastUsedDate(lastUsed, path: bundle)
    }

    static func wav(seconds: Double, frequency: Double, to path: String) {
        let rate = 44_100
        let count = Int(Double(rate) * seconds)
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let envelope = min(1, t * 4) * min(1, (seconds - t) * 4)
            let v = Int16(sin(2 * .pi * frequency * t) * 12_000 * envelope)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        header.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        try? (header + pcm).write(to: URL(fileURLWithPath: path))
    }

    // MARK: Pictures

    static func context(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// A card with big readable text (for OCR tests and screenshots).
    static func image(lines: [String], palette: [UInt32], dark: Bool = false, size: CGSize, to path: String) {
        guard let ctx = context(size) else { return }
        let colors = palette.map { cg($0) } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let card = NSRect(x: size.width * 0.1, y: size.height * 0.15, width: size.width * 0.8, height: size.height * 0.7)
        NSColor.white.withAlphaComponent(dark ? 0.0 : 0.88).setFill()
        NSBezierPath(roundedRect: card, xRadius: 36, yRadius: 36).fill()
        var y = card.maxY - size.height * 0.16
        for (i, line) in lines.enumerated() {
            let fontSize = (i == 0 ? 0.085 : 0.06) * size.height
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: i == 0 ? .bold : .medium),
                .foregroundColor: NSColor(white: 0.1, alpha: 1),
            ]
            (line as NSString).draw(at: NSPoint(x: card.minX + size.width * 0.06, y: y), withAttributes: attrs)
            y -= fontSize * 1.7
        }
        NSGraphicsContext.restoreGraphicsState()
        if let img = ctx.makeImage() { save(img, to: path, type: .png) }
    }

    /// A simple landscape: sky gradient, sun and hills. `brightness` nudges it for look-alike copies.
    static func scene(seed: Int, size: CGSize, to path: String, type: UTType, brightness: CGFloat = 0) {
        guard let ctx = context(size) else { return }
        let skies: [(UInt32, UInt32)] = [(0x87CEEB, 0xFFF1C7), (0x2B78E4, 0xA7D3FF), (0xFF9A61, 0xFFE3EC), (0x7352F0, 0xFFB4C6),
                                         (0xF2557F, 0xFFC93D), (0x1F3247, 0x64A6FF), (0x189E63, 0xD9F5E7), (0xC98A00, 0xFFF1C7)]
        let sky = skies[seed % skies.count]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(sky.0), cg(sky.1)] as CFArray, locations: nil) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
        }
        ctx.setFillColor(cg(0xFFF4B0, alpha: 0.95))
        let r = size.height * 0.12
        let sx = size.width * (0.2 + 0.6 * CGFloat((seed * 37) % 10) / 10)
        ctx.fillEllipse(in: CGRect(x: sx, y: size.height * 0.62, width: r * 2, height: r * 2))
        for layer in 0..<3 {
            let base = size.height * (0.18 + CGFloat(layer) * 0.12)
            ctx.setFillColor(cg([0x1F3D30, 0x2E6B4F, 0x4CD496][layer], alpha: 0.9))
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0
            while x <= size.width {
                let h = base + sin(CGFloat(seed + layer) + x / size.width * (4 + CGFloat(layer))) * size.height * 0.08
                ctx.addLine(to: CGPoint(x: x, y: h))
                x += size.width / 40
            }
            ctx.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.closePath()
            ctx.fillPath()
        }
        if brightness != 0 {
            ctx.setFillColor(CGColor(gray: 1, alpha: brightness))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        if let img = ctx.makeImage() { save(img, to: path, type: type) }
    }

    static func save(_ image: CGImage, to path: String, type: UTType) {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    static func pdf(lines: [String], to path: String) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        var y: CGFloat = 700
        for (i, line) in lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: i == 0 ? 30 : 16, weight: i == 0 ? .bold : .regular),
                .foregroundColor: NSColor.black,
            ]
            (line as NSString).draw(at: NSPoint(x: 64, y: y), withAttributes: attrs)
            y -= i == 0 ? 54 : 30
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
#endif
