import Foundation
import HavenCore

/// The shelf: a place to gather files from anywhere, then drag them all out at once. Remembered between launches.
@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()
    static let limit = 300

    private(set) var urls: [URL] = []

    private let key = "shelf"
    private var defaults: UserDefaults { LaunchOptions.current.defaults }

    private init() {
        urls = (defaults.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
        prune()
    }

    private func save() {
        defaults.set(urls.map(\.path), forKey: key)
    }

    /// Adds files (once each, newest last). Returns how many were new.
    @discardableResult
    func add(_ new: [URL]) -> Int {
        var have = Set(urls.map(\.path))
        var added = 0
        for url in new where url.isFileURL && have.insert(url.path).inserted {
            urls.append(URL(fileURLWithPath: url.path))
            added += 1
        }
        if urls.count > Self.limit { urls.removeFirst(urls.count - Self.limit) }
        if added > 0 { save() }
        return added
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.path == url.path }
        save()
    }

    func clear() {
        urls.removeAll()
        save()
    }

    /// Files that are gone (deleted, or on a drive that's no longer connected) leave the shelf.
    func prune() {
        let kept = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if kept.count != urls.count {
            urls = kept
            save()
        }
    }

    /// Follows files Haven renamed or moved.
    func follow(_ moves: [String: String]) {
        var changed = false
        urls = urls.map { url in
            if let to = moves[url.path] {
                changed = true
                return URL(fileURLWithPath: to)
            }
            return url
        }
        if changed { save() }
    }

    var totalBytes: Int64 {
        urls.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }
}
