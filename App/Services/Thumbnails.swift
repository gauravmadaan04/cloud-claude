import AppKit
import HavenCore
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
            let t = Thumbnail(image: rep.nsImage, isIcon: rep.type == .icon)
            cache.setObject(t, forKey: k, cost: Int(CGFloat(bucket * bucket) * scale * scale * 4))
            return t
        } catch {
            return await MainActor.run { Thumbnail(image: NSWorkspace.shared.icon(forFile: item.path), isIcon: true) }
        }
    }
}
