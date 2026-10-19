import AppKit
import AVFoundation
import HavenCore
import ImageIO
import PDFKit
import QuickLookThumbnailing

final class Thumbnail {
    let image: NSImage
    /// True when this is a generic file icon rather than a picture of the content.
    let isIcon: Bool

    init(image: NSImage, isIcon: Bool) {
        self.image = image
        self.isIcon = isIcon
    }
}

/// Big, real thumbnails from Quick Look, cached in memory.
final class Thumbnails: @unchecked Sendable {
    static let shared = Thumbnails()

    private let cache = NSCache<NSString, Thumbnail>()

    private init() {
        cache.countLimit = 2_500
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    static func bucket(_ side: CGFloat) -> Int {
        for b in [48, 96, 160, 256, 384, 512, 768] where CGFloat(b) >= side { return b }
        return 1024
    }

    private func key(_ item: FileItem, _ bucket: Int) -> NSString {
        "\(item.path)|\(Int(item.modified.timeIntervalSince1970))|\(bucket)" as NSString
    }

    func cached(_ item: FileItem, side: CGFloat) -> Thumbnail? {
        cache.object(forKey: key(item, Self.bucket(side)))
    }

    @MainActor
    func icon(for item: FileItem) -> Thumbnail {
        Thumbnail(image: NSWorkspace.shared.icon(forFile: item.path), isIcon: true)
    }

    func thumbnail(for item: FileItem, side: CGFloat, scale: CGFloat) async -> Thumbnail {
        let bucket = Self.bucket(side)
        let k = key(item, bucket)
        if let hit = cache.object(forKey: k) { return hit }
        // Folders, apps and iCloud-only files: use the Finder icon (nothing gets downloaded).
        if item.kind == .folder || item.kind == .app || item.isCloudOnly {
            let t = await MainActor.run { Thumbnail(image: NSWorkspace.shared.icon(forFile: item.path), isIcon: true) }
            cache.setObject(t, forKey: k, cost: bucket * bucket * 4)
            return t
        }
        let pixels = CGFloat(bucket) * max(1, scale)
        let cost = Int(pixels * pixels * 4)
        // Pictures: ImageIO is fast and doesn't depend on the Quick Look service.
        if item.kind == .image, item.ext != "svg" {
            let url = item.url
            if let image = await Task.detached(priority: .userInitiated, operation: { Self.imageThumbnail(url, maxPixel: pixels) }).value {
                let t = Thumbnail(image: image, isIcon: false)
                cache.setObject(t, forKey: k, cost: cost)
                return t
            }
        }
        if let t = await quickLook(item, bucket: bucket, scale: scale), !(t.isIcon && (item.kind == .pdf || item.kind == .video)) {
            cache.setObject(t, forKey: k, cost: cost)
            return t
        }
        // Quick Look gave up: draw PDFs and videos ourselves.
        let url = item.url
        let kind = item.kind
        let fallback: NSImage? = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            if kind == .pdf { return Self.pdfThumbnail(url, maxPixel: pixels) }
            return nil
        }.value
        if let fallback {
            let t = Thumbnail(image: fallback, isIcon: false)
            cache.setObject(t, forKey: k, cost: cost)
            return t
        }
        if kind == .video, let frame = await Self.videoThumbnail(url, maxPixel: pixels) {
            let t = Thumbnail(image: frame, isIcon: false)
            cache.setObject(t, forKey: k, cost: cost)
            return t
        }
        return await MainActor.run { Thumbnail(image: NSWorkspace.shared.icon(forFile: item.path), isIcon: true) }
    }

    private func quickLook(_ item: FileItem, bucket: Int, scale: CGFloat) async -> Thumbnail? {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: bucket, height: bucket),
            scale: scale,
            representationTypes: [.thumbnail, .icon]
        )
        do {
            let rep = try await withTaskCancellationHandler {
                try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            } onCancel: {
                QLThumbnailGenerator.shared.cancel(request)
            }
            return Thumbnail(image: rep.nsImage, isIcon: rep.type == .icon)
        } catch {
            return nil
        }
    }

    static func imageThumbnail(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func pdfThumbnail(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let ratio = maxPixel / max(bounds.width, bounds.height, 1)
        return page.thumbnail(of: CGSize(width: bounds.width * ratio, height: bounds.height * ratio), for: .mediaBox)
    }

    static func videoThumbnail(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let (cg, _) = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
