import AppKit
import Foundation
import HavenCore
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// "Make Shareable": JPEG copies of HEIC/PNG photos, smaller images, smaller PDFs and ZIPs. Always writes new
/// files next to the originals (which are never changed); Undo moves the copies to the Trash.
@MainActor
final class ShareMaker {
    static let shared = ShareMaker()
    private(set) var isWorking = false

    struct Outcome: Sendable {
        var made: [(from: String, to: String)] = []
        var failed = 0
        /// PDFs that were already as small as Haven can make them.
        var alreadySmall = 0
        var bytesBefore: Int64 = 0
        var bytesAfter: Int64 = 0
    }

    func run(_ kind: ShareNaming.Kind, items: [FileItem], undoManager: UndoManager?) {
        guard ShareNaming.applies(kind, to: items) else {
            AppModel.shared.showToast("“\(kind.title)” doesn't work for these files", symbol: "exclamationmark.triangle")
            return
        }
        guard !isWorking else { return }
        isWorking = true
        AppModel.shared.showToast(items.count == 1 ? "Working on “\(items[0].name)”…" : "Working on \(items.count) files…", symbol: kind.symbol)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { ShareMaker.make(kind, items: items) }.value
            self.isWorking = false
            self.report(kind, outcome, undoManager: undoManager)
        }
    }

    private func report(_ kind: ShareNaming.Kind, _ o: Outcome, undoManager: UndoManager?) {
        let entry = FileOps.shared.recordCreated(o.made, reason: kind.title, undoManager: undoManager)
        var message: String
        if o.made.isEmpty {
            message = o.alreadySmall > 0 ? "Already as small as it gets" : "Couldn't make a copy"
        } else if kind == .zip {
            message = "Made “\((o.made[0].to as NSString).lastPathComponent)” · \(ByteSize.format(o.bytesAfter))"
        } else if o.made.count == 1 {
            message = "Made “\((o.made[0].to as NSString).lastPathComponent)”"
            if o.bytesBefore > 0, kind != .jpeg { message += " · \(ByteSize.format(o.bytesBefore)) → \(ByteSize.format(o.bytesAfter))" }
        } else {
            message = "Made \(o.made.count) copies"
            if o.bytesBefore > 0, kind != .jpeg { message += " · \(ByteSize.format(o.bytesBefore)) → \(ByteSize.format(o.bytesAfter))" }
        }
        if o.failed > 0 { message += " (\(o.failed) couldn't be read)" }
        if o.alreadySmall > 0 && !o.made.isEmpty { message += " (\(o.alreadySmall) already small)" }
        AppModel.shared.showToast(message, symbol: o.made.isEmpty ? "exclamationmark.triangle" : kind.symbol, undoEntry: entry?.id)
    }

    // MARK: Making copies (any thread)

    nonisolated static func make(_ kind: ShareNaming.Kind, items: [FileItem]) -> Outcome {
        var o = Outcome()
        let fm = FileManager.default
        if kind == .zip {
            let dir = items[0].parentPath
            let dest = RulesPlanner.uniqueDestination(name: ShareNaming.zipName(for: items), in: dir) { fm.fileExists(atPath: $0) }
            if zip(items.map(\.url), to: URL(fileURLWithPath: dest)) {
                o.made.append((items.count == 1 ? items[0].path : dir, dest))
                o.bytesAfter = fileSize(dest)
            } else {
                o.failed = items.count
            }
            return o
        }
        for item in items {
            let dest = RulesPlanner.uniqueDestination(name: ShareNaming.outputName(for: item, kind: kind), in: item.parentPath) {
                fm.fileExists(atPath: $0)
            }
            let ok: Bool
            switch kind {
            case .jpeg: ok = jpeg(from: item.url, to: URL(fileURLWithPath: dest), maxSide: nil, quality: 0.88)
            case .smallerImage: ok = jpeg(from: item.url, to: URL(fileURLWithPath: dest), maxSide: 2048, quality: 0.8)
            case .smallerPDF:
                let result = smallerPDF(from: item.url, to: URL(fileURLWithPath: dest))
                if result == .alreadySmall { o.alreadySmall += 1; continue }
                ok = result == .made
            case .zip: ok = false
            }
            if ok {
                o.made.append((item.path, dest))
                o.bytesBefore += item.size
                o.bytesAfter += fileSize(dest)
            } else {
                try? fm.removeItem(atPath: dest)
                o.failed += 1
            }
        }
        return o
    }

    nonisolated static func fileSize(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// A JPEG copy, upright, with camera details kept and location removed. Transparent areas turn white.
    nonisolated static func jpeg(from url: URL, to dest: URL, maxSide: Int?, quality: Double) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return false }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return false }
        let target = maxSide.map { ShareNaming.smallerSide(width: width, height: height, target: $0) } ?? (width, height)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.0, target.1),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return false }
        let alpha = image.alphaInfo
        if alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast {
            guard let flat = flatten(image) else { return false }
            image = flat
        }
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        var meta: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let exif = props[kCGImagePropertyExifDictionary] { meta[kCGImagePropertyExifDictionary] = exif }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        meta[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(out, image, meta as CFDictionary)
        return CGImageDestinationFinalize(out)
    }

    nonisolated static func flatten(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    enum PDFResult { case made, alreadySmall, failed }

    /// Re-saves the PDF with its pictures downsampled (Haven's filter first, then macOS's own "Reduce File Size").
    nonisolated static func smallerPDF(from url: URL, to dest: URL) -> PDFResult {
        guard let doc = PDFDocument(url: url), !doc.isEncrypted || doc.isLocked == false else { return .failed }
        let original = fileSize(url.path)
        for filter in pdfFilters() {
            try? FileManager.default.removeItem(at: dest)
            guard doc.write(to: dest, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else { continue }
            let size = fileSize(dest.path)
            // Worth keeping only if it's clearly smaller and still opens.
            if size > 0, Double(size) < Double(original) * 0.9, PDFDocument(url: dest) != nil { return .made }
        }
        try? FileManager.default.removeItem(at: dest)
        return .alreadySmall
    }

    /// Pictures at up to 1600 px and JPEG quality 0.6 keep text sharp and photos fine on screen.
    nonisolated static func pdfFilters() -> [QuartzFilter] {
        var filters: [QuartzFilter] = []
        let plist: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": "Haven Smaller PDF",
            "FilterData": [
                "ColorSettings": [
                    "ImageSettings": [
                        "Compression Quality": 0.6,
                        "ImageCompression": "ImageJPEGCompress",
                        "ImageScaleSettings": [
                            "ImageScaleFactor": 0.0,
                            "ImageScaleInterpolate": true,
                            "ImageSizeMax": 1600,
                            "ImageSizeMin": 128,
                        ],
                    ],
                ],
            ],
        ]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("haven-smaller-pdf-\(UUID().uuidString).qfilter")
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           (try? data.write(to: file)) != nil {
            let custom: QuartzFilter? = QuartzFilter(url: file)
            if let custom { filters.append(custom) }
        }
        let system: QuartzFilter? = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter"))
        if let system { filters.append(system) }
        return filters
    }

    /// Finder-style ZIP (made by macOS's own `ditto`). Several files are gathered first (as instant APFS clones).
    nonisolated static func zip(_ urls: [URL], to dest: URL) -> Bool {
        let fm = FileManager.default
        var source = urls[0]
        var keepParent = true
        var staging: URL?
        if urls.count > 1 {
            let dir = fm.temporaryDirectory.appendingPathComponent("haven-zip-\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                var used = Set<String>()
                for url in urls {
                    var name = url.lastPathComponent
                    var n = 2
                    while !used.insert(name.lowercased()).inserted {
                        name = "\((url.lastPathComponent as NSString).deletingPathExtension) \(n)" + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
                        n += 1
                    }
                    try fm.copyItem(at: url, to: dir.appendingPathComponent(name))
                }
            } catch {
                try? fm.removeItem(at: dir)
                return false
            }
            source = dir
            keepParent = false
            staging = dir
        }
        defer { if let staging { try? fm.removeItem(at: staging) } }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc"] + (keepParent ? ["--keepParent"] : []) + [source.path, dest.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0 && fm.fileExists(atPath: dest.path)
    }
}
