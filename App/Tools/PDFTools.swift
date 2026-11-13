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

/// Merging, splitting, reordering, passwords, and filling in and signing, with PDFKit. Always writes new files.
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

    /// Fill & Sign: draws what was added onto the pages and saves a new PDF. A page with something added (or, when
    /// the form is locked, a page with form fields) is redrawn with everything on it as plain page content, links
    /// kept. A page with a redaction becomes a picture, so what was under the black box is gone for good.
    /// Every other page is kept exactly as it was, form fields and all.
    static func fill(_ plan: FillPlan, dest: URL) throws {
        guard let doc = PDFDocument(data: plan.base), !doc.isLocked else { throw ToolError.failed("Couldn't read the document") }
        let byPage = Dictionary(grouping: plan.items, by: \.page)
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let items = byPage[index] ?? []
            let hasFields = page.annotations.contains { $0.type == "Widget" }
            let replacement: PDFPage?
            if items.contains(where: { $0.content.isRedaction }) {
                replacement = rasterize(page, items: items)
            } else if !items.isEmpty || (plan.lockForm && hasFields) {
                replacement = flatten(page, items: items)
            } else {
                continue
            }
            guard let made = replacement else { throw ToolError.failed("Couldn't write page \(index + 1)") }
            doc.removePage(at: index)
            doc.insert(made, at: index)
        }
        try save(doc, to: dest)
    }

    /// The page with its form answers, highlights and notes drawn in as plain content, and the added items on top.
    static func flatten(_ page: PDFPage, items: [FillItem]) -> PDFPage? {
        let media = page.bounds(for: .mediaBox)
        let data = NSMutableData()
        var box = media
        guard let cgPage = page.pageRef, let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        drawFilled(page, cgPage: cgPage, items: items, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let made = PDFDocument(data: data as Data)?.page(at: 0) else { return nil }
        match(made, to: page)
        for link in page.annotations where link.type == "Link" {
            if let copy = link.copy() as? PDFAnnotation { made.addAnnotation(copy) }
        }
        return made
    }

    /// The page as a picture (200 dpi), with the redactions burnt in: no text survives under them.
    static func rasterize(_ page: PDFPage, items: [FillItem], dpi: CGFloat = 200) -> PDFPage? {
        let media = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let w = Int((media.width * scale).rounded()), h = Int((media.height * scale).rounded())
        guard let cgPage = page.pageRef, w > 0, h > 0,
              let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: w, height: h))
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.translateBy(x: -media.minX, y: -media.minY)
        drawFilled(page, cgPage: cgPage, items: items, in: bitmap)
        guard let picture = bitmap.makeImage() else { return nil }
        let image = jpeg(picture, quality: 0.86) ?? picture
        let data = NSMutableData()
        var box = media
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: media)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let made = PDFDocument(data: data as Data)?.page(at: 0) else { return nil }
        match(made, to: page)
        return made
    }

    /// Page content, then every annotation's appearance (form fields with their answers, highlights, notes), then the
    /// items, all in the page's own coordinates.
    private static func drawFilled(_ page: PDFPage, cgPage: CGPDFPage, items: [FillItem], in ctx: CGContext) {
        ctx.drawPDFPage(cgPage)
        for a in page.annotations where a.type != "Link" && a.type != "Popup" && a.shouldDisplay && !(a is FillAnnotation) {
            ctx.saveGState()
            a.draw(with: .mediaBox, in: ctx)
            ctx.restoreGState()
        }
        for item in items { FillDrawing.draw(item, rotation: page.rotation, in: ctx) }
    }

    /// A new page shows like the old one: same turn, same visible area.
    private static func match(_ made: PDFPage, to page: PDFPage) {
        made.rotation = page.rotation
        let crop = page.bounds(for: .cropBox)
        if crop != page.bounds(for: .mediaBox) { made.setBounds(crop, for: .cropBox) }
    }

    /// The picture as JPEG data, so a page that became a picture stays a sensible size.
    private static func jpeg(_ image: CGImage, quality: Double) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let src = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Text a PDF holds, for translating and summarizing.
    static func text(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
        let s = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
}
