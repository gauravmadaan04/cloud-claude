import Foundation
import HavenCore
import ImageIO

/// Plans renames off the main thread with everything the planner may need: text Haven read from the files,
/// when photos were taken, and what's already in each folder.
enum RenameService {
    static func plan(_ items: [FileItem], template: RenameTemplate) async -> [RenameChange] {
        let store = await LibraryStore.shared.text.store
        return await Task.detached(priority: .userInitiated) {
            let context = RenameContext(text: { store.raw(for: $0.path) }, takenDate: { RenameService.takenDate($0) })
            var listings: [String: [String]] = [:]
            return RenamePlanner.plan(items, template: template, context: context) { dir in
                if let known = listings[dir] { return known }
                let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                listings[dir] = names
                return names
            }
        }.value
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var takenCache: [String: Date?] = [:]

    /// When a photo or video was taken (from its EXIF), remembered per file version.
    static func takenDate(_ item: FileItem) -> Date? {
        guard item.kind == .image || item.kind == .video else { return nil }
        let key = "\(item.path)|\(item.modified.timeIntervalSince1970)"
        lock.lock()
        if let hit = takenCache[key] { lock.unlock(); return hit }
        lock.unlock()
        var date: Date?
        if item.kind == .image, let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            if let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String {
                date = exifFormatter.date(from: raw)
            }
        }
        lock.lock()
        if takenCache.count > 20_000 { takenCache.removeAll() }
        takenCache[key] = .some(date)
        lock.unlock()
        return date
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}
