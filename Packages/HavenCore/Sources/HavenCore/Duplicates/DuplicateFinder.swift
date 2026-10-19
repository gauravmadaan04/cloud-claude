import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum DuplicateKind: String, Codable, Sendable, Hashable {
    /// Byte-for-byte the same (SHA-256 match).
    case identical
    /// Look-alike photos: bursts, edits, HEIC/JPEG pairs.
    case similar
}

public struct DuplicateGroup: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: DuplicateKind
    public var items: [FileItem]
    /// Path Haven suggests keeping.
    public var suggestedKeep: String

    public init(id: String, kind: DuplicateKind, items: [FileItem], suggestedKeep: String) {
        self.id = id
        self.kind = kind
        self.items = items
        self.suggestedKeep = suggestedKeep
    }

    /// Bytes freed by trashing everything except the kept copy.
    public var reclaimableBytes: Int64 {
        items.filter { $0.path != suggestedKeep }.reduce(0) { $0 + $1.size }
    }
}

public enum FileHasher {
    /// SHA-256 of a file's contents, streamed in 1 MB chunks. Returns nil if it can't be read.
    public static func sha256(of url: URL, cancelled: () -> Bool = { false }) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        #if canImport(CryptoKit)
        var hasher = SHA256()
        while true {
            if cancelled() { return nil }
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1 << 20) ?? Data() } catch { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        var hasher = PortableSHA256()
        while true {
            if cancelled() { return nil }
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1 << 20) ?? Data() } catch { return nil }
            if chunk.isEmpty { break }
            hasher.update(chunk)
        }
        return hasher.finalizeHex()
        #endif
    }

    /// Hash of the first 64 KB, used to cheaply split same-size files before hashing them fully.
    public static func headHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return nil }
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var h = PortableSHA256()
        h.update(data)
        return h.finalizeHex()
        #endif
    }
}

public enum DuplicateFinder {

    /// Kinds worth checking for exact duplicates (folders, apps and bundles are skipped).
    static func eligible(_ item: FileItem) -> Bool {
        guard !item.isCloudOnly, item.size > 0 else { return false }
        switch item.kind {
        case .folder, .app: return false
        default: break
        }
        // Bundles like .pages/.key are directories; hashing them would be wrong.
        return isRegularFile(item)
    }

    /// The checks that need no disk access.
    static func quickEligible(_ item: FileItem) -> Bool {
        guard !item.isCloudOnly, item.size > 0 else { return false }
        return item.kind != .folder && item.kind != .app
    }

    static func isRegularFile(_ item: FileItem) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue { return false }
        return true
    }

    /// Groups byte-identical files: size first, then a 64 KB head hash, then full SHA-256.
    /// `hashCache` lets callers reuse hashes keyed by "path|size|mtime".
    public static func identicalGroups(
        in items: [FileItem],
        minSize: Int64 = 1,
        hashCache: inout [String: String],
        progress: ((Int, Int) -> Void)? = nil,
        cancelled: () -> Bool = { false }
    ) -> [DuplicateGroup] {
        var bySize: [Int64: [FileItem]] = [:]
        for item in items where item.size >= minSize && quickEligible(item) {
            bySize[item.size, default: []].append(item)
        }
        // Only files that share a size are looked at on disk.
        let candidates = bySize.values.compactMap { same -> [FileItem]? in
            guard same.count > 1 else { return nil }
            let real = same.filter(eligible)
            return real.count > 1 ? real : nil
        }
        let total = candidates.reduce(0) { $0 + $1.count }
        var done = 0
        var reported = -1
        var groups: [DuplicateGroup] = []

        for sameSize in candidates {
            if cancelled() { break }
            var byHead: [String: [FileItem]] = [:]
            for item in sameSize {
                // Head hashes are cached too, so unchanged files aren't read again on the next run.
                let headKey = "head|" + cacheKey(item)
                let head: String?
                if let cached = hashCache[headKey] {
                    head = cached
                } else {
                    head = FileHasher.headHash(of: item.url)
                    if let head { hashCache[headKey] = head }
                }
                if let head { byHead[head, default: []].append(item) }
            }
            for heads in byHead.values where heads.count > 1 {
                var byFull: [String: [FileItem]] = [:]
                for item in heads {
                    if cancelled() { break }
                    let key = cacheKey(item)
                    let hash: String?
                    if let cached = hashCache[key] {
                        hash = cached
                    } else if item.size <= 64 * 1024 {
                        // The head hash already covered the whole file.
                        hash = FileHasher.headHash(of: item.url)
                        if let hash { hashCache[key] = hash }
                    } else {
                        hash = FileHasher.sha256(of: item.url, cancelled: cancelled)
                        if let hash { hashCache[key] = hash }
                    }
                    if let hash { byFull[hash, default: []].append(item) }
                }
                for (hash, same) in byFull where same.count > 1 {
                    let keep = suggestKeeper(same, kind: .identical)
                    groups.append(DuplicateGroup(id: "sha:" + hash, kind: .identical, items: sortedForDisplay(same, keep: keep), suggestedKeep: keep.path))
                }
            }
            done += sameSize.count
            let percent = total == 0 ? 100 : done * 100 / total
            if percent != reported {
                reported = percent
                progress?(done, total)
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// The copies to trash given the user's Keep/Trash picks, made safe:
    /// - every group keeps at least one copy (Haven's pick when every copy was marked Trash);
    /// - a group is left alone unless one of its kept copies is still there exactly as compared;
    /// - a copy that changed since it was compared is never trashed.
    public static func safeToTrash(groups: [DuplicateGroup], keeps: (FileItem, DuplicateGroup) -> Bool,
                                   unchanged: (FileItem) -> Bool) -> [FileItem] {
        var out: [FileItem] = []
        for g in groups {
            var kept = g.items.filter { keeps($0, g) }
            var trash = g.items.filter { !keeps($0, g) }
            if kept.isEmpty {
                let keeper = g.items.first { $0.path == g.suggestedKeep } ?? g.items.first
                guard let keeper else { continue }
                kept = [keeper]
                trash = g.items.filter { $0.path != keeper.path }
            }
            guard kept.contains(where: unchanged) else { continue }
            out += trash.filter(unchanged)
        }
        return out
    }

    /// True when the file on disk still has the size and modification time it had when it was compared.
    public static func isUnchanged(_ item: FileItem) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let modified = attrs[.modificationDate] as? Date else { return false }
        return size == item.size && abs(modified.timeIntervalSince(item.modified)) < 1
    }

    public static func cacheKey(_ item: FileItem) -> String {
        "\(item.path)|\(item.size)|\(Int(item.modified.timeIntervalSince1970))"
    }

    static func sortedForDisplay(_ items: [FileItem], keep: FileItem) -> [FileItem] {
        [keep] + items.filter { $0.path != keep.path }.sorted { $0.activityDate < $1.activityDate }
    }

    /// Picks the copy to keep. Identical files: the one with a clean name, outside Downloads, oldest.
    /// Similar photos: the one with the most pixels (passed in through `pixels`), then the largest file.
    public static func suggestKeeper(_ items: [FileItem], kind: DuplicateKind, pixels: [String: Int] = [:]) -> FileItem {
        precondition(!items.isEmpty)
        switch kind {
        case .identical:
            return items.max { keeperScore($0) < keeperScore($1) }!
        case .similar:
            return items.max { a, b in
                let pa = pixels[a.path] ?? 0, pb = pixels[b.path] ?? 0
                if pa != pb { return pa < pb }
                if a.size != b.size { return a.size < b.size }
                return keeperScore(a) < keeperScore(b)
            }!
        }
    }

    /// Higher is better.
    static func keeperScore(_ item: FileItem) -> Double {
        var score = 0.0
        let base = FileItem.fold(item.baseName)
        if looksLikeCopy(base) { score -= 50 }
        if item.rootID == "downloads" { score -= 20 }
        if item.rootID == "desktop" { score -= 5 }
        // Older original wins ties; scaled to stay below the name and folder penalties.
        score -= item.created.timeIntervalSince1970 / 1e9
        // Shallower paths read as more "organised".
        score -= Double(item.path.split(separator: "/").count) * 0.1
        return score
    }

    static func looksLikeCopy(_ base: String) -> Bool {
        if base.hasSuffix(" copy") || base.contains(" copy ") { return true }
        // "name (1)", "name (2)", "name-1", "name_2", "name 2"
        let patterns = [#"\(\d+\)$"#, #"[-_ ]\d$"#, #"copy \d+$"#, #"^copy of "#]
        for p in patterns where base.range(of: p, options: .regularExpression) != nil { return true }
        return false
    }
}

/// Groups look-alike photos given pairwise distances. Pure logic: Vision lives in the app.
public enum SimilarityClusterer {

    /// Name without extension and without copy/edit markers ("IMG_E1234 (1)" → "img_1234").
    public static func stem(_ item: FileItem) -> String {
        var s = FileItem.fold(item.baseName)
        for p in [#" \(\d+\)$"#, #" copy( \d+)?$"#, #"[-_ ](edited|edit)$"#, #"-\d$"#] {
            if let r = s.range(of: p, options: .regularExpression) { s.removeSubrange(r) }
        }
        // Apple's edited photos: IMG_E1234 → IMG_1234
        if let r = s.range(of: #"^img_e(\d+)"#, options: .regularExpression) {
            let digits = s[r].dropFirst(5)
            s.replaceSubrange(r, with: "img_" + digits)
        }
        return s
    }

    /// Pairs worth comparing: same stem (HEIC/JPEG pairs, edits) or taken within `window` seconds of each other
    /// (bursts). `date` lets callers pass capture dates; defaults to creation date.
    public static func candidatePairs(_ images: [FileItem], window: TimeInterval = 120, date: ((FileItem) -> Date)? = nil) -> [(Int, Int)] {
        var pairs = Set<Pair>()
        var byStem: [String: [Int]] = [:]
        for (i, item) in images.enumerated() {
            byStem[item.parentPath + "/" + stem(item), default: []].append(i)
        }
        for idx in byStem.values where idx.count > 1 {
            for a in 0..<idx.count {
                for b in (a + 1)..<idx.count { pairs.insert(Pair(idx[a], idx[b])) }
            }
        }
        let dateOf = date ?? { $0.created }
        let order = images.indices.sorted { dateOf(images[$0]) < dateOf(images[$1]) }
        for (pos, i) in order.enumerated() {
            let di = dateOf(images[i])
            var next = pos + 1
            // Cap each window so a folder of thousands of same-second exports stays cheap.
            var compared = 0
            while next < order.count, compared < 12 {
                let j = order[next]
                if dateOf(images[j]).timeIntervalSince(di) > window { break }
                pairs.insert(Pair(i, j))
                next += 1
                compared += 1
            }
        }
        return pairs.map { ($0.a, $0.b) }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
    }

    struct Pair: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
    }

    /// Union-find over pairs whose distance is below `threshold`. Returns clusters of 2+ indexes.
    public static func clusters(count: Int, pairs: [(Int, Int)], threshold: Float, distance: (Int, Int) -> Float?) -> [[Int]] {
        var parent = Array(0..<count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for (a, b) in pairs {
            guard let d = distance(a, b), d <= threshold else { continue }
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<count { groups[find(i), default: []].append(i) }
        return groups.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}
