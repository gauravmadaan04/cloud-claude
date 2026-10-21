import AppKit
import HavenCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// One page in the page organizer: where it came from and how far it's turned.
struct PageEdit: Hashable, Identifiable {
    let source: Int
    var rotation = 0
    var id: Int { source }
}

/// Merging, splitting, reordering, passwords and signatures, with PDFKit. Always writes new files.
enum PDFTools {
    static func open(_ url: URL, password: String? = nil) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw ToolError.unreadable(url.lastPathComponent) }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw password == nil ? ToolError.locked(url.lastPathComponent) : ToolError.wrongPassword
            }
        }
        return doc
    }

    static func isLocked(_ url: URL) -> Bool { PDFDocument(url: url)?.isEncrypted ?? false }

    static func pageCount(_ url: URL) -> Int { PDFDocument(url: url)?.pageCount ?? 0 }

    private static func save(_ doc: PDFDocument, to dest: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard doc.write(to: dest, withOptions: options) else {
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.failed("Couldn't save “\(dest.lastPathComponent)”")
        }
    }

    /// Every page of every PDF, in order, into one.
    @discardableResult
    static func merge(_ urls: [URL], dest: URL) throws -> Int {
        let out = PDFDocument()
        for url in urls {
            let doc = try open(url)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                out.insert(page, at: out.pageCount)
            }
        }
        guard out.pageCount > 0 else { throw ToolError.failed("There were no pages to merge") }
        try save(out, to: dest)
        return out.pageCount
    }

    /// One PDF per page, in a new folder.
    static func split(_ url: URL, into folder: URL, base: String) throws -> [URL] {
        let doc = try open(url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var made: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let dest = folder.appendingPathComponent(ToolNaming.page(base, i, of: doc.pageCount, ext: "pdf"))
            try save(single, to: dest)
            made.append(dest)
        }
        return made
    }

    /// A new PDF with the pages in the order given, each turned as asked. Pages left out are left out.
    @discardableResult
    static func rebuild(_ url: URL, pages: [PageEdit], dest: URL) throws -> Int {
        let doc = try open(url)
        let out = PDFDocument()
        for edit in pages where edit.source >= 0 && edit.source < doc.pageCount {
            guard let page = doc.page(at: edit.source)?.copy() as? PDFPage else { continue }
            page.rotation = ((page.rotation + edit.rotation) % 360 + 360) % 360
            out.insert(page, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw ToolError.failed("Pick at least one page") }
        try save(out, to: dest)
        return out.pageCount
    }

    /// Photos and scans into one PDF, a page each (shaped like the picture). JPEG data goes in as is.
    @discardableResult
    static func imagesToPDF(_ urls: [URL], dest: URL) throws -> Int {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(dest as CFURL, mediaBox: &box, nil) else { throw ToolError.failed("Couldn't create the PDF") }
        var pages = 0
        for url in urls {
            guard let image = pageImage(url) else { continue }
            // The long side becomes 842 pt (A4's height), so pages print at a sensible size.
            let scale = 842 / CGFloat(max(image.width, image.height))
            var media = CGRect(x: 0, y: 0, width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: media)
            ctx.endPDFPage()
            pages += 1
        }
        ctx.closePDF()
        guard pages > 0 else {
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.failed("None of the images could be read")
        }
        return pages
    }

    /// An upright picture for a PDF page, as JPEG data (photos) so the PDF stays small.
    static func pageImage(_ url: URL) -> CGImage? {
        guard let s = try? ImageTools.source(url),
              let upright = try? ImageTools.upright(s.0, props: s.1, maxSide: 4000) else { return nil }
        if ImageTools.hasAlpha(upright) { return upright }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return upright }
        CGImageDestinationAddImage(dest, upright, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let jsrc = CGImageSourceCreateWithData(data, nil),
              let jpeg = CGImageSourceCreateImageAtIndex(jsrc, 0, nil) else { return upright }
        return jpeg
    }

    /// Every page as a PNG (150 dpi, crisp on screen), in a new folder.
    static func toImages(_ url: URL, into folder: URL, base: String, dpi: CGFloat = 150, progress: ((Double) -> Void)? = nil) throws -> [URL] {
        let doc = try open(url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var made: [URL] = []
        for i in 0..<doc.pageCount {
            try Task.checkCancellation()
            guard let page = doc.page(at: i), let image = render(page, dpi: dpi) else { continue }
            let dest = folder.appendingPathComponent(ToolNaming.page(base, i, of: doc.pageCount, ext: "png"))
            try ImageTools.write(image, as: .png, to: dest, props: [:])
            made.append(dest)
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        return made
    }

    /// A page as a picture, the way it's shown (rotation included), on white.
    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let turned = page.rotation % 180 != 0
        let scale = dpi / 72
        let w = Int(((turned ? bounds.height : bounds.width) * scale).rounded())
        let h = Int(((turned ? bounds.width : bounds.height) * scale).rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// A copy that needs the password to open.
    static func lock(_ url: URL, password: String, dest: URL) throws {
        guard !password.isEmpty else { throw ToolError.failed("Type a password") }
        let doc = try open(url)
        try save(doc, to: dest, options: [.userPasswordOption: password, .ownerPasswordOption: password])
    }

    /// A copy that opens without a password.
    static func unlock(_ url: URL, password: String, dest: URL) throws {
        let doc = try open(url, password: password)
        // A fresh document, so nothing of the old protection comes along.
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i)?.copy() as? PDFPage { out.insert(page, at: out.pageCount) }
        }
        try save(out, to: dest)
    }

    /// Places a signature picture on a page. `rect` is in the page's own coordinates (as PDFView reports them).
    /// Only that page is redrawn with the signature; every other page is kept exactly as it was.
    static func sign(_ url: URL, page index: Int, rect: CGRect, signature: CGImage, dest: URL) throws {
        let doc = try open(url)
        guard let page = doc.page(at: index), let cgPage = page.pageRef else { throw ToolError.failed("That page isn't there") }
        let media = page.bounds(for: .mediaBox)
        let data = NSMutableData()
        var box = media
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ToolError.failed("Couldn't sign") }
        ctx.beginPDFPage(nil)
        ctx.drawPDFPage(cgPage)
        // The page may be shown turned: turn the signature the other way so it reads upright.
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: CGFloat(page.rotation) * .pi / 180)
        let turned = page.rotation % 180 != 0
        let w = turned ? rect.height : rect.width, h = turned ? rect.width : rect.height
        ctx.interpolationQuality = .high
        ctx.draw(signature, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
        ctx.endPDFPage()
        ctx.closePDF()
        guard let signedDoc = PDFDocument(data: data as Data), let signedPage = signedDoc.page(at: 0) else { throw ToolError.failed("Couldn't sign") }
        signedPage.rotation = page.rotation
        doc.removePage(at: index)
        doc.insert(signedPage, at: index)
        try save(doc, to: dest)
    }

    /// Text a PDF holds, for translating and summarizing.
    static func text(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
        let s = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
}
